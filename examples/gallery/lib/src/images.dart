/// Turning a picture into the tensor a vision model expects.
///
/// Decoding goes through `dart:ui`, which every platform Flutter runs on
/// already has, rather than through an image package: the work here is a
/// resize and an arithmetic rescale, and pulling in a decoder to do it would
/// be more dependency than problem.
///
/// The two conventions in this app differ and both are the model's, not a
/// choice made here. SqueezeNet and MobileNet want NCHW float32 normalised
/// with the ImageNet mean and standard deviation. Tiny YOLOv3 wants NCHW
/// float32 in 0..1 with the original size passed alongside, because it reports
/// boxes in the coordinates of the picture it was given rather than of the
/// square it was resized into.
library;

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

/// A decoded picture, kept as straight RGBA bytes.
class Picture {
  const Picture({
    required this.width,
    required this.height,
    required this.rgba,
  });

  final int width;
  final int height;
  final Uint8List rgba;

  /// Decodes an encoded image, whatever format the platform can read.
  static Future<Picture> decode(Uint8List encoded) async {
    final codec = await ui.instantiateImageCodec(encoded);
    final frame = await codec.getNextFrame();
    final image = frame.image;
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (data == null) {
        throw StateError('the platform decoded the image and then would not '
            'hand back its bytes');
      }
      return Picture(
        width: image.width,
        height: image.height,
        rgba: data.buffer.asUint8List(),
      );
    } finally {
      image.dispose();
      codec.dispose();
    }
  }

  /// Nearest-neighbour resize to an exact size, ignoring aspect ratio.
  ///
  /// Not the best resampling available, and deliberately: a bilinear resize
  /// would make the classifier look slightly better and would hide which part
  /// of the pipeline any disagreement between two runs came from.
  Picture resized(int toWidth, int toHeight) {
    final out = Uint8List(toWidth * toHeight * 4);
    for (var y = 0; y < toHeight; y++) {
      final sourceY = (y * height ~/ toHeight).clamp(0, height - 1);
      for (var x = 0; x < toWidth; x++) {
        final sourceX = (x * width ~/ toWidth).clamp(0, width - 1);
        final from = (sourceY * width + sourceX) * 4;
        final to = (y * toWidth + x) * 4;
        out[to] = rgba[from];
        out[to + 1] = rgba[from + 1];
        out[to + 2] = rgba[from + 2];
        out[to + 3] = rgba[from + 3];
      }
    }
    return Picture(width: toWidth, height: toHeight, rgba: out);
  }

  /// Scales so the shorter side is [side], keeping the aspect ratio.
  Picture shorterSide(int side) {
    final scale = side / (width < height ? width : height);
    return resized((width * scale).round(), (height * scale).round());
  }

  /// The middle [side] by [side] square.
  Picture centreCrop(int side) {
    final left = ((width - side) ~/ 2).clamp(0, width);
    final top = ((height - side) ~/ 2).clamp(0, height);
    final take = side.clamp(1, width < height ? width : height);
    final out = Uint8List(take * take * 4);
    for (var y = 0; y < take; y++) {
      final from = ((top + y) * width + left) * 4;
      out.setRange(y * take * 4, (y + 1) * take * 4, rgba, from);
    }
    return Picture(width: take, height: take, rgba: out);
  }

  /// Fits the whole picture into a [side] square, padding what is left over.
  ///
  /// What YOLO expects: the aspect ratio is preserved so a box the model
  /// reports lines up with the object, and the padding is the mid grey the
  /// model was trained to ignore.
  Picture letterboxed(int side) {
    final scale = side / (width > height ? width : height);
    final inner = resized((width * scale).round(), (height * scale).round());
    final out = Uint8List(side * side * 4)..fillRange(0, side * side * 4, 128);
    final left = (side - inner.width) ~/ 2;
    final top = (side - inner.height) ~/ 2;
    for (var y = 0; y < inner.height; y++) {
      final to = ((top + y) * side + left) * 4;
      out.setRange(to, to + inner.width * 4, inner.rgba, y * inner.width * 4);
    }
    // Alpha, which fillRange set to 128 along with everything else.
    for (var i = 3; i < out.length; i += 4) {
      out[i] = 255;
    }
    return Picture(width: side, height: side, rgba: out);
  }
}

/// ImageNet's channel means and standard deviations, in RGB order.
const imagenetMean = [0.485, 0.456, 0.406];
const imagenetDeviation = [0.229, 0.224, 0.225];

/// NCHW float32, rescaled to 0..1 and then standardised.
///
/// What SqueezeNet and MobileNet were trained on. Getting this wrong does not
/// fail, it just returns confident nonsense, which is why the numbers are
/// written out rather than folded into a constant.
Float32List asImagenetInput(Picture picture, int side) {
  // Resize the shorter side to 256 and take the middle 224, which is what the
  // model card specifies. Squashing the whole frame into a square instead
  // keeps every margin the photographer left, and a subject with a lot of
  // white around it then classifies as whatever that white looks like.
  final scaled = picture.shorterSide(side * 256 ~/ 224).centreCrop(side);
  final out = Float32List(3 * side * side);
  final plane = side * side;
  for (var i = 0; i < plane; i++) {
    for (var channel = 0; channel < 3; channel++) {
      final value = scaled.rgba[i * 4 + channel] / 255.0;
      out[channel * plane + i] =
          (value - imagenetMean[channel]) / imagenetDeviation[channel];
    }
  }
  return out;
}

/// NCHW float32 in 0..1, which is what Tiny YOLOv3 takes.
Float32List asUnitInput(Picture picture, int side) {
  final scaled = picture.letterboxed(side);
  final out = Float32List(3 * side * side);
  final plane = side * side;
  for (var i = 0; i < plane; i++) {
    for (var channel = 0; channel < 3; channel++) {
      out[channel * plane + i] = scaled.rgba[i * 4 + channel] / 255.0;
    }
  }
  return out;
}

/// Whether [scores] are already probabilities.
///
/// Some exported classifiers end in a softmax and some do not, and the two
/// look identical from outside: both are a thousand floats. SqueezeNet 1.0-12
/// includes one, MobileNet v2 does not. Applying softmax twice does not fail,
/// it flattens every class to about a thousandth, which reads as a model that
/// recognised nothing rather than as a bug here.
///
/// The test is what the definition of a probability distribution is: no
/// negatives, and they sum to one.
bool looksLikeProbabilities(List<double> scores) {
  if (scores.isEmpty) return false;
  var total = 0.0;
  for (final score in scores) {
    if (score < 0) return false;
    total += score;
  }
  return (total - 1.0).abs() < 0.01;
}

/// Probabilities for [scores], whichever form the model produced them in.
List<double> asProbabilities(List<double> scores) =>
    looksLikeProbabilities(scores) ? scores : softmax(scores);

/// Turns scores into probabilities, so the top few can be compared.
List<double> softmax(List<double> scores) {
  if (scores.isEmpty) return const [];
  final highest = scores.reduce((a, b) => a > b ? a : b);
  var total = 0.0;
  final out = List<double>.filled(scores.length, 0);
  for (var i = 0; i < scores.length; i++) {
    // Shifted by the maximum first: exp of a raw logit overflows.
    final value = math.exp(scores[i] - highest);
    out[i] = value;
    total += value;
  }
  for (var i = 0; i < out.length; i++) {
    out[i] /= total;
  }
  return out;
}

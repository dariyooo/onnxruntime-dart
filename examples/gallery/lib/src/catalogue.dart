/// The models this app can run, and where they come from.
///
/// Upstream only. Every entry points at the project that published the model,
/// not at a copy made here, because a converted model is one whose behaviour
/// this project would have to explain rather than ONNX Runtime's.
///
/// Sizes are recorded rather than discovered so the app can say what a download
/// will cost before it starts spending. They are checked against the server on
/// download, and a mismatch is reported rather than ignored: a size that has
/// drifted means the file has, and silently fetching a different model than the
/// one described is worse than failing.
library;

/// What part of the runtime a model is here to exercise.
enum ModelKind {
  classifier('Classifier'),
  detector('Object detector'),
  recurrent('Recurrent'),
  transformer('Transformer'),
  generative('Generative');

  const ModelKind(this.label);
  final String label;
}

/// One file to fetch.
class RemoteFile {
  const RemoteFile({
    required this.url,
    required this.name,
    required this.bytes,
  });

  final String url;

  /// What it is called on disk, which for a GenAI model is also where in the
  /// model directory it has to land.
  final String name;

  /// Size in bytes, as published.
  final int bytes;
}

/// A model, everything needed to fetch it, and what it is for.
class ModelSpec {
  const ModelSpec({
    required this.id,
    required this.name,
    required this.kind,
    required this.source,
    required this.sourceUrl,
    required this.files,
    required this.what,
    required this.exercises,
    this.licence,
  });

  final String id;
  final String name;
  final ModelKind kind;

  /// Who published it, shown so a reader can tell it is not from here.
  final String source;
  final String sourceUrl;

  final List<RemoteFile> files;

  /// One line on what the model does.
  final String what;

  /// Why it is in this app rather than another model of the same kind.
  final String exercises;

  final String? licence;

  /// What fetching it will cost, in bytes.
  int get bytes => files.fold(0, (total, file) => total + file.bytes);

  /// The main graph, which for every entry here is the first file.
  RemoteFile get model => files.first;
}

const _zoo = 'https://github.com/onnx/models/raw/main/validated';

const _phi3 = 'https://huggingface.co/microsoft/Phi-3-mini-4k-instruct-onnx/'
    'resolve/main/cpu_and_mobile/cpu-int4-rtn-block-32-acc-level-4';

/// The stem the Phi-3 files share, which is long enough to be worth naming
/// once. GenAI reads it out of genai_config.json, so it has to land on disk
/// under exactly this name.
const _phi3Stem = 'phi3-mini-4k-instruct-cpu-int4-rtn-block-32-acc-level-4';

/// The thousand ImageNet class names, in the order the classifiers score them.
///
/// Upstream as well: a label list that disagrees with the model turns a
/// correct answer into a wrong one, so it comes from the same place.
const _imagenetLabels = RemoteFile(
  url: '$_zoo/vision/classification/synset.txt',
  name: 'synset.txt',
  bytes: 31675,
);

/// The catalogue, smallest first so the first thing a reader tries is cheap.
const catalogue = <ModelSpec>[
  ModelSpec(
    id: 'squeezenet',
    name: 'SqueezeNet 1.1',
    kind: ModelKind.classifier,
    source: 'ONNX Model Zoo',
    sourceUrl: 'https://github.com/onnx/models',
    licence: 'Apache-2.0',
    what: 'Names what is in a photograph, from a thousand ImageNet classes.',
    exercises: 'The plain path: one float input, one float output, no dynamic '
        'dimensions. If this does not run, nothing else will.',
    files: [
      RemoteFile(
        // 1.1 rather than 1.0. The 1.0 files in the zoo are the Caffe
        // conversion and want BGR with the mean subtracted and no scaling,
        // which is a second preprocessing convention for one model. 1.1 uses
        // the torchvision one, the same as MobileNet below.
        url: '$_zoo/vision/classification/squeezenet/model/'
            'squeezenet1.1-7.onnx',
        name: 'squeezenet1.1-7.onnx',
        bytes: 4956208,
      ),
      _imagenetLabels,
    ],
  ),
  ModelSpec(
    id: 'mobilenet',
    name: 'MobileNet v2',
    kind: ModelKind.classifier,
    source: 'ONNX Model Zoo',
    sourceUrl: 'https://github.com/onnx/models',
    licence: 'Apache-2.0',
    what: 'The same thousand classes, more accurately and more slowly.',
    exercises: 'Depthwise convolution, which is where CPU and GPU builds most '
        'often disagree about numerics.',
    files: [
      RemoteFile(
        url: '$_zoo/vision/classification/mobilenet/model/mobilenetv2-12.onnx',
        name: 'mobilenetv2-12.onnx',
        bytes: 13964571,
      ),
      _imagenetLabels,
    ],
  ),
  ModelSpec(
    id: 'tiny-yolov3',
    name: 'Tiny YOLOv3',
    kind: ModelKind.detector,
    source: 'ONNX Model Zoo',
    sourceUrl: 'https://github.com/onnx/models',
    licence: 'MIT',
    what: 'Finds objects in a photograph and says where they are.',
    exercises: 'Several outputs of different ranks, and a free batch '
        'dimension, so the shape handling has to be real rather than assumed.',
    files: [
      RemoteFile(
        url: '$_zoo/vision/object_detection_segmentation/tiny-yolov3/model/'
            'tiny-yolov3-11.onnx',
        name: 'tiny-yolov3-11.onnx',
        bytes: 35511756,
      ),
    ],
  ),
  ModelSpec(
    id: 'bidaf',
    name: 'BiDAF',
    kind: ModelKind.recurrent,
    source: 'ONNX Model Zoo',
    sourceUrl: 'https://github.com/onnx/models',
    licence: 'MIT',
    what: 'Answers a question by pointing at the span of a passage that '
        'contains the answer.',
    exercises: 'LSTMs, and string tensors on both the way in and the way out, '
        'which almost nothing else in this list touches.',
    files: [
      RemoteFile(
        url: '$_zoo/text/machine_comprehension/'
            'bidirectional_attention_flow/model/bidaf-9.onnx',
        name: 'bidaf-9.onnx',
        bytes: 43522228,
      ),
    ],
  ),
  ModelSpec(
    id: 'minilm',
    name: 'all-MiniLM-L6-v2',
    kind: ModelKind.transformer,
    source: 'sentence-transformers',
    sourceUrl: 'https://huggingface.co/sentence-transformers/all-MiniLM-L6-v2',
    licence: 'Apache-2.0',
    what: 'Turns a sentence into a vector, so two sentences can be compared '
        'by meaning rather than by wording.',
    exercises: 'Attention, int64 inputs, and three inputs at once. The output '
        'is a vector rather than a label, so the comparison is arithmetic.',
    files: [
      RemoteFile(
        url: 'https://huggingface.co/sentence-transformers/all-MiniLM-L6-v2/'
            'resolve/main/onnx/model.onnx',
        name: 'minilm.onnx',
        bytes: 90405214,
      ),
      RemoteFile(
        url: 'https://huggingface.co/sentence-transformers/all-MiniLM-L6-v2/'
            'resolve/main/vocab.txt',
        name: 'vocab.txt',
        bytes: 231508,
      ),
    ],
  ),
  ModelSpec(
    id: 'phi3-mini',
    name: 'Phi-3 mini 4k instruct',
    kind: ModelKind.generative,
    source: 'Microsoft',
    sourceUrl: 'https://huggingface.co/microsoft/Phi-3-mini-4k-instruct-onnx',
    licence: 'MIT',
    what: 'Answers in prose, a token at a time.',
    exercises: 'The GenAI package rather than the runtime directly: its own '
        'tokenizer, its own generation loop, and a model too large to hold '
        'twice, so the weights arrive in a separate file beside the graph.',
    files: [
      // The graph first, because `model` is defined as the first file. The
      // weights follow in .onnx.data, which is nearly all of the download.
      RemoteFile(
        url: '$_phi3/$_phi3Stem.onnx',
        name: '$_phi3Stem.onnx',
        bytes: 231335,
      ),
      RemoteFile(
        url: '$_phi3/$_phi3Stem.onnx.data',
        name: '$_phi3Stem.onnx.data',
        bytes: 2722861056,
      ),
      // GenAI reads this to find everything else, so without it the directory
      // is just files.
      RemoteFile(
        url: '$_phi3/genai_config.json',
        name: 'genai_config.json',
        bytes: 1576,
      ),
      RemoteFile(
        url: '$_phi3/tokenizer.json',
        name: 'tokenizer.json',
        bytes: 1937869,
      ),
      RemoteFile(
        url: '$_phi3/tokenizer_config.json',
        name: 'tokenizer_config.json',
        bytes: 3441,
      ),
      RemoteFile(
        url: '$_phi3/special_tokens_map.json',
        name: 'special_tokens_map.json',
        bytes: 599,
      ),
      RemoteFile(
        url: '$_phi3/added_tokens.json',
        name: 'added_tokens.json',
        bytes: 306,
      ),
      RemoteFile(
        url: '$_phi3/config.json',
        name: 'config.json',
        bytes: 919,
      ),
    ],
  ),
];

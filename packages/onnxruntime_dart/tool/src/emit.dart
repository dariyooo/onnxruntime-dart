/// Emits Dart wrappers for the C API.
///
/// Each function becomes a method that takes Dart values, allocates whatever
/// the call needs in an arena, checks the returned `OrtStatus`, and returns the
/// out-parameters. Ownership follows the SAL annotation: an `_Outptr_ OrtX**`
/// hands back an `OrtX` the caller must release, which is the rule rather than
/// a per-function decision.
library;

import 'c_api.dart';
import 'ffigen_api.dart';
import 'types.dart';

/// Groups functions into files, most specific pattern first.
///
/// Filing only. Every function that can be wrapped is wrapped, so a name none
/// of these match lands in [_fallbackGroup] rather than being dropped.
const groups = <String, String>{
  'kernel': r'Kernel|CustomOp|ShapeInfer|^Op$|^Op[A-Z]|OpAttr|^InvokeOp',
  'graph': r'^Graph$|^Graph_|^Node$|^Node_|ValueInfo|^Model_|^OpaqueValue|'
      r'Initializer',
  'ep': r'^Ep[A-Z_]|EpFactory|EpGraph|EpDevice|NodeCompute|HardwareDevice|'
      r'DeviceEp|SyncStream|^RegisterExecutionProvider|^UnregisterExecutionProvider',
  'training': r'Training|Lora|Adapter',
  'sparse': r'Sparse|DLPack|TuningResult|^Use(Coo|Csr|Block)',
  'binding': r'IoBinding|^Bind|^ClearBound|^GetBound|^SynchronizeBound',
  'memory': r'MemoryInfo|Allocator|Arena|MemPattern|^CreateAndRegister|'
      r'PrepackedWeights',
  'session':
      r'^(Create|Release|Clone)?Session|^Run$|RunAsync|RunWithBinding|Profiling',
  'options':
      r'SessionOptions|RunOptions|ThreadingOptions|SetGlobal|ConfigEntry|'
          r'FreeDimensionOverride|Env$|^CreateEnv|^ReleaseEnv|^Enable|^Disable|'
          r'^SetSession|^SetInter|^SetIntra|^SetDeterministic|^SetOptimized|'
          r'^SetLanguageProjection|^SetGlobal|^SetEp|^SetLoad|^SetCurrentGpu|'
          r'^UpdateEnv|PerSessionThreadPool|SessionExecutionMode',
  'tensor': r'Tensor|Value|Dimensions|Symbolic|TypeInfo|MapType|MapKeyType|'
      r'SequenceType|SequenceElementType|OnnxType',
  'provider': r'Provider|ExecutionProvider|GetAvailable|Compat',
  'model': r'ModelMetadata|Metadata|^Compile|^Model',
  'status': r'^GetErrorCode|^GetErrorMessage|^CreateStatus|^ReleaseStatus|'
      r'Logger|^Log$|Telemetry',
};

/// Where a function lands when no pattern claims it.
const _fallbackGroup = 'core';

/// Calls that keep a buffer the caller passed, with what the header says.
///
/// The signature cannot express this and the SAL annotation does not mark it,
/// so it is read out of the header's prose and repeated in the wrapper's
/// documentation. Passing a pointer that dies first is the highest-risk
/// mistake available here, and silence is what makes it easy.
const retainedBuffers = <String, String>{
  'CreateTensorWithDataAsOrtValue':
      'the tensor is a view over `pData` and does not copy it, so that '
          'allocation must outlive the tensor',
  'CreateSparseTensorWithValuesAsOrtValue':
      'the tensor is a view over `pData` and does not copy it, so that '
          'allocation must outlive the tensor',
  'CreateTensorFromMemory':
      'the tensor is a view over the imported memory, which must outlive it',
  'AddInitializer':
      'the runtime keeps `val` rather than copying it, so it must outlive '
          'every session created from these options',
  'AddInitializerToGraph':
      'the graph keeps `tensor` rather than copying it, so it must outlive '
          'the graph',
};

/// The file a function belongs in.
///
/// A release files with the type it releases, so `ReleaseGraph` sits next to
/// the graph calls rather than wherever its own name happens to match.
String groupOf(String name) {
  final released = RegExp(r'^Release(\w+)$').firstMatch(name)?.group(1);
  return _match(released) ?? _match(name) ?? _fallbackGroup;
}

String? _match(String? name) {
  if (name == null) return null;
  for (final entry in groups.entries) {
    if (RegExp(entry.value).hasMatch(name)) return entry.key;
  }
  return null;
}

/// A Dart identifier from a C one: `SessionGetInputCount` to
/// `sessionGetInputCount`.
///
/// Member access is written `this.Name` because `package:ffi` exports
/// extensions that collide with struct member names.
String dartName(String name) => name[0].toLowerCase() + name.substring(1);

/// Emits the wrapper for [function], or null when it cannot be mapped.
///
/// [signature] is the same function as ffigen typed it, which is what the
/// emitted `asFunction` has to agree with.
String? emit(CFunction function, Signature signature) {
  final askThenFill = emitAskThenFill(function, signature);
  if (askThenFill != null) return askThenFill;
  if (!isFullyMapped(function)) return null;
  if (signature.length != function.parameters.length) return null;

  final inputs = <(CParameter, InputMapping)>[];
  final outputs = <(CParameter, OutputMapping)>[];
  for (final parameter in function.parameters) {
    switch (map(parameter)) {
      case final InputMapping m:
        inputs.add((parameter, m));
      case final OutputMapping m:
        outputs.add((parameter, m));
      case Unmapped():
        return null;
    }
  }

  // A scalar mapping leaves its Dart type to the signature, so that `bool` and
  // `double` are not mistaken for `int` on the way out.
  String typeOf(CParameter parameter, Mapping mapping) {
    final declared = switch (mapping) {
      InputMapping(:final dartType) ||
      OutputMapping(:final dartType) =>
        dartType,
      Unmapped() => null,
    };
    final ffi = signature[function.parameters.indexOf(parameter)];
    final element =
        declared ?? _callType(mapping is OutputMapping ? _pointee(ffi) : ffi);
    return mapping is OutputMapping && parameter.arrayLengthParameter != null
        ? 'List<$element>'
        : element;
  }

  // An out-parameter that only carries the length of a callee-allocated array
  // is allocated like any other but not returned: the list says the same thing,
  // and returning both invites them to disagree.
  final counts = {
    for (final parameter in function.parameters)
      if (parameter.isCalleeAllocated && parameter.arrayLengthParameter != null)
        parameter.arrayLengthParameter!,
  };
  final returned = outputs.where((o) => !counts.contains(o.$1.name)).toList();

  final returnType = switch (returned.length) {
    0 => 'void',
    1 => typeOf(returned.single.$1, returned.single.$2),
    _ => '(${returned.map((o) => '${typeOf(o.$1, o.$2)} '
        '${_dartParam(o.$1.name)}').join(', ')})',
  };

  final parameters = inputs
      .map((i) => '${typeOf(i.$1, i.$2)} ${_dartParam(i.$1.name)}')
      .join(', ');

  // `asFunction` is typed with the Dart signature, so scalars cross as `int`
  // and `double` even though the field they come from is typed in FFI terms.
  // A callback keeps the typedef ffigen gave it, which is already a pointer
  // and so is the same on both sides.
  final callSignature = [
    for (final (index, ffi) in signature.indexed)
      function.parameters[index].isFunctionPointer ? ffi : _callType(ffi),
  ].join(', ');

  // An out-parameter is `Pointer<X>`, so `X` is what the arena allocates. An
  // out-array allocates as many as its length parameter says.
  final allocations = StringBuffer();
  for (final (index, (parameter, _)) in outputs.indexed) {
    final cell = _pointee(signature[function.parameters.indexOf(parameter)]);
    final length = parameter.arrayLengthParameter;
    // A callee-allocated array needs one pointer cell whatever its length: the
    // call fills that cell with an array it allocated itself.
    final count =
        length == null || parameter.isCalleeAllocated ? '' : _dartParam(length);
    allocations.writeln('        final ${_out(index)} = arena<$cell>($count);');
  }

  final outputIndex = {
    for (final (index, (parameter, _)) in outputs.indexed)
      parameter.name: index,
  };
  final arguments = function.parameters.map((p) {
    final mapping = map(p);
    return mapping is OutputMapping
        ? _out(outputIndex[p.name]!)
        : (mapping as InputMapping).marshal(_dartParam(p.name));
  }).join(', ');

  // Nothing to free means no arena: a release takes a handle and returns, and
  // wrapping that in a scope allocates more than the call does.
  final needsArena = outputs.isNotEmpty ||
      inputs.any((i) => i.$2.marshal(_dartParam(i.$1.name)).contains('arena'));

  final call = 'this.${function.name}.asFunction<'
      '${function.returnsStatus ? 'Pointer<OrtStatus>' : 'void'} '
      'Function($callSignature)>()($arguments)';
  final statement = function.returnsStatus ? 'checkOrtStatus($call)' : call;

  if (!needsArena) {
    final body = outputs.isEmpty ? statement : throw StateError(function.name);
    return '${_doc(function.name)}'
        '  $returnType ${dartName(function.name)}($parameters) => $body;\n';
  }

  final buffer = StringBuffer()
    ..write(_doc(function.name))
    ..writeln('  $returnType ${dartName(function.name)}($parameters) =>')
    ..writeln('      withArena((arena) {')
    ..write(allocations)
    ..writeln('        $statement;');

  // Which allocator this call was handed, for the reads that free with it.
  final allocator = function.parameters
      .where((p) => p.type.contains('OrtAllocator'))
      .map((p) => _dartParam(p.name))
      .firstOrNull;

  final outputSlot = {
    for (final (index, (parameter, _)) in outputs.indexed)
      parameter.name: index,
  };

  String read(CParameter parameter, OutputMapping mapping, int index) {
    final length = parameter.arrayLengthParameter;
    // The length of a callee-allocated array is itself an out-parameter, so it
    // is read from its own cell rather than named as a Dart argument.
    final count = length == null
        ? null
        : parameter.isCalleeAllocated
            ? '${_out(outputSlot[length]!)}.value'
            : _dartParam(length);
    final text = count == null
        ? mapping.read(_out(index))
        : (mapping.readArray ?? mapping.readAll)(_out(index), count);
    if (!mapping.needsAllocator) return text;
    if (allocator == null) {
      throw StateError(
        '${function.name} frees allocator memory but takes no allocator',
      );
    }
    return text.replaceAll('ALLOCATOR', allocator);
  }

  switch (returned.length) {
    case 0:
      break;
    case 1:
      final (parameter, mapping) = returned.single;
      buffer.writeln(
        '        return ${read(parameter, mapping, outputSlot[parameter.name]!)};',
      );
    default:
      final reads = returned
          .map((o) => read(o.$1, o.$2, outputSlot[o.$1.name]!))
          .join(', ');
      buffer.writeln('        return ($reads);');
  }

  buffer.writeln('      });');
  return buffer.toString();
}

/// Avoids colliding with Dart keywords and with our own locals.
String _dartParam(String name) {
  const reserved = {'in', 'out', 'is', 'default', 'this', 'new', 'var'};
  final camel = name
      .split('_')
      .indexed
      .map((e) =>
          e.$1 == 0 ? e.$2 : '${e.$2[0].toUpperCase()}${e.$2.substring(1)}')
      .join();
  return reserved.contains(camel) ? '${camel}_' : camel;
}

/// The wrapper's doc comment: the C name, and any warning it carries.
String _doc(String name) {
  final buffer = StringBuffer('  /// `$name`\n');
  if (retainedBuffers[name] case final warning?) {
    buffer.writeln('  ///');
    for (final line in _wrap('Borrows, does not copy: $warning.')) {
      buffer.writeln('  /// $line');
    }
  }
  return buffer.toString();
}

/// Wraps to what is left of eighty columns after the comment marker.
///
/// `dart format` leaves comments alone, so a long line stays long.
List<String> _wrap(String text, {int width = 74}) {
  final lines = <String>[];
  final current = StringBuffer();
  for (final word in text.split(' ')) {
    if (current.isNotEmpty && current.length + 1 + word.length > width) {
      lines.add(current.toString());
      current.clear();
    }
    if (current.isNotEmpty) current.write(' ');
    current.write(word);
  }
  if (current.isNotEmpty) lines.add(current.toString());
  return lines;
}

String _out(int index) => 'out$index';

/// The Dart-side spelling of an FFI type, for the `asFunction` signature.
///
/// Listed rather than inferred, and unknown types throw: a width guessed wrong
/// here produces Dart that analyzes cleanly and fails to compile, so failing at
/// generation time is the cheaper place to find out.
String _callType(String ffiType) {
  if (ffiType.startsWith('Pointer<')) return ffiType;
  return switch (ffiType) {
    'Int8' ||
    'Int16' ||
    'Int32' ||
    'Int64' ||
    'Uint8' ||
    'Uint16' ||
    'Uint32' ||
    'Uint64' ||
    'IntPtr' ||
    'UintPtr' ||
    'Char' ||
    'SignedChar' ||
    'UnsignedChar' ||
    'Short' ||
    'UnsignedShort' ||
    'Int' ||
    'UnsignedInt' ||
    'Long' ||
    'UnsignedLong' ||
    'LongLong' ||
    'UnsignedLongLong' ||
    'Size' ||
    'WChar' =>
      'int',
    'Float' || 'Double' => 'double',
    'Bool' => 'bool',
    _ => throw StateError('no Dart type for the FFI type $ffiType'),
  };
}

/// `X` from `Pointer<X>`.
String _pointee(String type) {
  if (!type.startsWith('Pointer<') || !type.endsWith('>')) {
    throw StateError('out-parameter is not a pointer: $type');
  }
  return type.substring('Pointer<'.length, type.length - 1);
}

/// The ask-then-fill pattern: call once for the size, once for the contents.
///
/// A run of functions ends `_Out_ T* out, _Inout_ size_t* size`, meaning the
/// caller does not know how much to allocate and asks first. Passing null for
/// the buffer makes the call report the size it wants and fail, which is not
/// an error here, so that status is discarded rather than checked. The second
/// call, with a buffer that size, is the one whose status matters.
///
/// Wrapped as a rule rather than by hand because the shape is identical across
/// the KernelInfo accessors and the two attribute-array readers, and a
/// hand-written wrapper each would be the same twelve lines rewritten.
///
/// For `char*` the size counts bytes and includes the terminator, so the
/// result is read as a string. For `float*` and `int64_t*` it counts elements
/// and the result is a list.
String? emitAskThenFill(CFunction function, Signature signature) {
  if (function.parameters.length < 2) return null;
  if (signature.length != function.parameters.length) return null;

  final size = function.parameters.last;
  final out = function.parameters[function.parameters.length - 2];
  if (size.direction != Direction.inout || size.type != 'size_t*') return null;
  if (out.direction != Direction.output) return null;
  if (out.arrayLengthParameter != null) return null;

  final cell = _pointee(signature[function.parameters.length - 2]);
  const elements = '[for (var i = 0; i < size.value; i++) buffer[i]]';
  final ({String type, String read})? result = switch (out.type) {
    'char*' => (type: 'String', read: 'buffer.cast<Utf8>().toDartString()'),
    'float*' => (type: 'List<double>', read: elements),
    'int64_t*' => (type: 'List<int>', read: elements),
    _ => null,
  };
  if (result == null) return null;
  final returnType = result.type;
  final read = result.read;

  // Everything before the buffer has to marshal like any other input.
  final leading =
      function.parameters.take(function.parameters.length - 2).toList();
  final marshalled = <String>[];
  for (final parameter in leading) {
    final mapping = map(parameter);
    if (mapping is! InputMapping) return null;
    marshalled.add(mapping.marshal(_dartParam(parameter.name)));
  }

  final parameters = [
    for (final (index, parameter) in leading.indexed)
      '${(map(parameter) as InputMapping).dartType ?? _callType(signature[index])} '
          '${_dartParam(parameter.name)}',
  ].join(', ');
  final callSignature = signature.map(_callType).join(', ');
  final arguments = marshalled.join(', ');

  return '${_doc(function.name)}'
      '  $returnType ${dartName(function.name)}($parameters) =>\n'
      '      withArena((arena) {\n'
      '        final size = arena<Size>()..value = 0;\n'
      '        final call = this.${function.name}.asFunction<\n'
      '            Pointer<OrtStatus> Function($callSignature)>();\n'
      '\n'
      '        // Reports the size it wants and fails because there is no\n'
      '        // buffer yet. Expected, so the status is released, not checked.\n'
      '        final asked = call($arguments${arguments.isEmpty ? '' : ', '}nullptr, size);\n'
      '        if (asked != nullptr) {\n'
      '          ReleaseStatus.asFunction<void Function(Pointer<OrtStatus>)>()(asked);\n'
      '        }\n'
      '\n'
      '        final buffer = arena<$cell>(size.value == 0 ? 1 : size.value);\n'
      '        checkOrtStatus(call($arguments${arguments.isEmpty ? '' : ', '}buffer, size));\n'
      '        return $read;\n'
      '      });\n';
}

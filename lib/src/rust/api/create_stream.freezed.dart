// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'create_stream.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$BridgeCreateUpdate {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeCreateUpdate);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'BridgeCreateUpdate()';
}


}

/// @nodoc
class $BridgeCreateUpdateCopyWith<$Res>  {
$BridgeCreateUpdateCopyWith(BridgeCreateUpdate _, $Res Function(BridgeCreateUpdate) __);
}


/// Adds pattern-matching-related methods to [BridgeCreateUpdate].
extension BridgeCreateUpdatePatterns on BridgeCreateUpdate {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeCreateUpdate_Progress value)?  progress,TResult Function( BridgeCreateUpdate_Complete value)?  complete,TResult Function( BridgeCreateUpdate_Error value)?  error,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeCreateUpdate_Progress() when progress != null:
return progress(_that);case BridgeCreateUpdate_Complete() when complete != null:
return complete(_that);case BridgeCreateUpdate_Error() when error != null:
return error(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeCreateUpdate_Progress value)  progress,required TResult Function( BridgeCreateUpdate_Complete value)  complete,required TResult Function( BridgeCreateUpdate_Error value)  error,}){
final _that = this;
switch (_that) {
case BridgeCreateUpdate_Progress():
return progress(_that);case BridgeCreateUpdate_Complete():
return complete(_that);case BridgeCreateUpdate_Error():
return error(_that);}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeCreateUpdate_Progress value)?  progress,TResult? Function( BridgeCreateUpdate_Complete value)?  complete,TResult? Function( BridgeCreateUpdate_Error value)?  error,}){
final _that = this;
switch (_that) {
case BridgeCreateUpdate_Progress() when progress != null:
return progress(_that);case BridgeCreateUpdate_Complete() when complete != null:
return complete(_that);case BridgeCreateUpdate_Error() when error != null:
return error(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String message)?  progress,TResult Function( BridgeShed shed)?  complete,TResult Function( String message)?  error,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeCreateUpdate_Progress() when progress != null:
return progress(_that.message);case BridgeCreateUpdate_Complete() when complete != null:
return complete(_that.shed);case BridgeCreateUpdate_Error() when error != null:
return error(_that.message);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String message)  progress,required TResult Function( BridgeShed shed)  complete,required TResult Function( String message)  error,}) {final _that = this;
switch (_that) {
case BridgeCreateUpdate_Progress():
return progress(_that.message);case BridgeCreateUpdate_Complete():
return complete(_that.shed);case BridgeCreateUpdate_Error():
return error(_that.message);}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String message)?  progress,TResult? Function( BridgeShed shed)?  complete,TResult? Function( String message)?  error,}) {final _that = this;
switch (_that) {
case BridgeCreateUpdate_Progress() when progress != null:
return progress(_that.message);case BridgeCreateUpdate_Complete() when complete != null:
return complete(_that.shed);case BridgeCreateUpdate_Error() when error != null:
return error(_that.message);case _:
  return null;

}
}

}

/// @nodoc


class BridgeCreateUpdate_Progress extends BridgeCreateUpdate {
  const BridgeCreateUpdate_Progress({required this.message}): super._();
  

 final  String message;

/// Create a copy of BridgeCreateUpdate
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeCreateUpdate_ProgressCopyWith<BridgeCreateUpdate_Progress> get copyWith => _$BridgeCreateUpdate_ProgressCopyWithImpl<BridgeCreateUpdate_Progress>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeCreateUpdate_Progress&&(identical(other.message, message) || other.message == message));
}


@override
int get hashCode => Object.hash(runtimeType,message);

@override
String toString() {
  return 'BridgeCreateUpdate.progress(message: $message)';
}


}

/// @nodoc
abstract mixin class $BridgeCreateUpdate_ProgressCopyWith<$Res> implements $BridgeCreateUpdateCopyWith<$Res> {
  factory $BridgeCreateUpdate_ProgressCopyWith(BridgeCreateUpdate_Progress value, $Res Function(BridgeCreateUpdate_Progress) _then) = _$BridgeCreateUpdate_ProgressCopyWithImpl;
@useResult
$Res call({
 String message
});




}
/// @nodoc
class _$BridgeCreateUpdate_ProgressCopyWithImpl<$Res>
    implements $BridgeCreateUpdate_ProgressCopyWith<$Res> {
  _$BridgeCreateUpdate_ProgressCopyWithImpl(this._self, this._then);

  final BridgeCreateUpdate_Progress _self;
  final $Res Function(BridgeCreateUpdate_Progress) _then;

/// Create a copy of BridgeCreateUpdate
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? message = null,}) {
  return _then(BridgeCreateUpdate_Progress(
message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class BridgeCreateUpdate_Complete extends BridgeCreateUpdate {
  const BridgeCreateUpdate_Complete({required this.shed}): super._();
  

 final  BridgeShed shed;

/// Create a copy of BridgeCreateUpdate
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeCreateUpdate_CompleteCopyWith<BridgeCreateUpdate_Complete> get copyWith => _$BridgeCreateUpdate_CompleteCopyWithImpl<BridgeCreateUpdate_Complete>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeCreateUpdate_Complete&&(identical(other.shed, shed) || other.shed == shed));
}


@override
int get hashCode => Object.hash(runtimeType,shed);

@override
String toString() {
  return 'BridgeCreateUpdate.complete(shed: $shed)';
}


}

/// @nodoc
abstract mixin class $BridgeCreateUpdate_CompleteCopyWith<$Res> implements $BridgeCreateUpdateCopyWith<$Res> {
  factory $BridgeCreateUpdate_CompleteCopyWith(BridgeCreateUpdate_Complete value, $Res Function(BridgeCreateUpdate_Complete) _then) = _$BridgeCreateUpdate_CompleteCopyWithImpl;
@useResult
$Res call({
 BridgeShed shed
});




}
/// @nodoc
class _$BridgeCreateUpdate_CompleteCopyWithImpl<$Res>
    implements $BridgeCreateUpdate_CompleteCopyWith<$Res> {
  _$BridgeCreateUpdate_CompleteCopyWithImpl(this._self, this._then);

  final BridgeCreateUpdate_Complete _self;
  final $Res Function(BridgeCreateUpdate_Complete) _then;

/// Create a copy of BridgeCreateUpdate
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? shed = null,}) {
  return _then(BridgeCreateUpdate_Complete(
shed: null == shed ? _self.shed : shed // ignore: cast_nullable_to_non_nullable
as BridgeShed,
  ));
}


}

/// @nodoc


class BridgeCreateUpdate_Error extends BridgeCreateUpdate {
  const BridgeCreateUpdate_Error({required this.message}): super._();
  

 final  String message;

/// Create a copy of BridgeCreateUpdate
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeCreateUpdate_ErrorCopyWith<BridgeCreateUpdate_Error> get copyWith => _$BridgeCreateUpdate_ErrorCopyWithImpl<BridgeCreateUpdate_Error>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeCreateUpdate_Error&&(identical(other.message, message) || other.message == message));
}


@override
int get hashCode => Object.hash(runtimeType,message);

@override
String toString() {
  return 'BridgeCreateUpdate.error(message: $message)';
}


}

/// @nodoc
abstract mixin class $BridgeCreateUpdate_ErrorCopyWith<$Res> implements $BridgeCreateUpdateCopyWith<$Res> {
  factory $BridgeCreateUpdate_ErrorCopyWith(BridgeCreateUpdate_Error value, $Res Function(BridgeCreateUpdate_Error) _then) = _$BridgeCreateUpdate_ErrorCopyWithImpl;
@useResult
$Res call({
 String message
});




}
/// @nodoc
class _$BridgeCreateUpdate_ErrorCopyWithImpl<$Res>
    implements $BridgeCreateUpdate_ErrorCopyWith<$Res> {
  _$BridgeCreateUpdate_ErrorCopyWithImpl(this._self, this._then);

  final BridgeCreateUpdate_Error _self;
  final $Res Function(BridgeCreateUpdate_Error) _then;

/// Create a copy of BridgeCreateUpdate
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? message = null,}) {
  return _then(BridgeCreateUpdate_Error(
message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on

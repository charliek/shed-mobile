// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'mint.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$BridgeMintOutcome {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeMintOutcome);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'BridgeMintOutcome()';
}


}

/// @nodoc
class $BridgeMintOutcomeCopyWith<$Res>  {
$BridgeMintOutcomeCopyWith(BridgeMintOutcome _, $Res Function(BridgeMintOutcome) __);
}


/// Adds pattern-matching-related methods to [BridgeMintOutcome].
extension BridgeMintOutcomePatterns on BridgeMintOutcome {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeMintOutcome_Success value)?  success,TResult Function( BridgeMintOutcome_Failure value)?  failure,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeMintOutcome_Success() when success != null:
return success(_that);case BridgeMintOutcome_Failure() when failure != null:
return failure(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeMintOutcome_Success value)  success,required TResult Function( BridgeMintOutcome_Failure value)  failure,}){
final _that = this;
switch (_that) {
case BridgeMintOutcome_Success():
return success(_that);case BridgeMintOutcome_Failure():
return failure(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeMintOutcome_Success value)?  success,TResult? Function( BridgeMintOutcome_Failure value)?  failure,}){
final _that = this;
switch (_that) {
case BridgeMintOutcome_Success() when success != null:
return success(_that);case BridgeMintOutcome_Failure() when failure != null:
return failure(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String rawStdout)?  success,TResult Function( String code)?  failure,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeMintOutcome_Success() when success != null:
return success(_that.rawStdout);case BridgeMintOutcome_Failure() when failure != null:
return failure(_that.code);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String rawStdout)  success,required TResult Function( String code)  failure,}) {final _that = this;
switch (_that) {
case BridgeMintOutcome_Success():
return success(_that.rawStdout);case BridgeMintOutcome_Failure():
return failure(_that.code);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String rawStdout)?  success,TResult? Function( String code)?  failure,}) {final _that = this;
switch (_that) {
case BridgeMintOutcome_Success() when success != null:
return success(_that.rawStdout);case BridgeMintOutcome_Failure() when failure != null:
return failure(_that.code);case _:
  return null;

}
}

}

/// @nodoc


class BridgeMintOutcome_Success extends BridgeMintOutcome {
  const BridgeMintOutcome_Success({required this.rawStdout}): super._();
  

 final  String rawStdout;

/// Create a copy of BridgeMintOutcome
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeMintOutcome_SuccessCopyWith<BridgeMintOutcome_Success> get copyWith => _$BridgeMintOutcome_SuccessCopyWithImpl<BridgeMintOutcome_Success>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeMintOutcome_Success&&(identical(other.rawStdout, rawStdout) || other.rawStdout == rawStdout));
}


@override
int get hashCode => Object.hash(runtimeType,rawStdout);

@override
String toString() {
  return 'BridgeMintOutcome.success(rawStdout: $rawStdout)';
}


}

/// @nodoc
abstract mixin class $BridgeMintOutcome_SuccessCopyWith<$Res> implements $BridgeMintOutcomeCopyWith<$Res> {
  factory $BridgeMintOutcome_SuccessCopyWith(BridgeMintOutcome_Success value, $Res Function(BridgeMintOutcome_Success) _then) = _$BridgeMintOutcome_SuccessCopyWithImpl;
@useResult
$Res call({
 String rawStdout
});




}
/// @nodoc
class _$BridgeMintOutcome_SuccessCopyWithImpl<$Res>
    implements $BridgeMintOutcome_SuccessCopyWith<$Res> {
  _$BridgeMintOutcome_SuccessCopyWithImpl(this._self, this._then);

  final BridgeMintOutcome_Success _self;
  final $Res Function(BridgeMintOutcome_Success) _then;

/// Create a copy of BridgeMintOutcome
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? rawStdout = null,}) {
  return _then(BridgeMintOutcome_Success(
rawStdout: null == rawStdout ? _self.rawStdout : rawStdout // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class BridgeMintOutcome_Failure extends BridgeMintOutcome {
  const BridgeMintOutcome_Failure({required this.code}): super._();
  

 final  String code;

/// Create a copy of BridgeMintOutcome
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeMintOutcome_FailureCopyWith<BridgeMintOutcome_Failure> get copyWith => _$BridgeMintOutcome_FailureCopyWithImpl<BridgeMintOutcome_Failure>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeMintOutcome_Failure&&(identical(other.code, code) || other.code == code));
}


@override
int get hashCode => Object.hash(runtimeType,code);

@override
String toString() {
  return 'BridgeMintOutcome.failure(code: $code)';
}


}

/// @nodoc
abstract mixin class $BridgeMintOutcome_FailureCopyWith<$Res> implements $BridgeMintOutcomeCopyWith<$Res> {
  factory $BridgeMintOutcome_FailureCopyWith(BridgeMintOutcome_Failure value, $Res Function(BridgeMintOutcome_Failure) _then) = _$BridgeMintOutcome_FailureCopyWithImpl;
@useResult
$Res call({
 String code
});




}
/// @nodoc
class _$BridgeMintOutcome_FailureCopyWithImpl<$Res>
    implements $BridgeMintOutcome_FailureCopyWith<$Res> {
  _$BridgeMintOutcome_FailureCopyWithImpl(this._self, this._then);

  final BridgeMintOutcome_Failure _self;
  final $Res Function(BridgeMintOutcome_Failure) _then;

/// Create a copy of BridgeMintOutcome
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? code = null,}) {
  return _then(BridgeMintOutcome_Failure(
code: null == code ? _self.code : code // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on

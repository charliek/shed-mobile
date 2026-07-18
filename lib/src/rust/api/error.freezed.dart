// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'error.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$BridgeError {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeError);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'BridgeError()';
}


}

/// @nodoc
class $BridgeErrorCopyWith<$Res>  {
$BridgeErrorCopyWith(BridgeError _, $Res Function(BridgeError) __);
}


/// Adds pattern-matching-related methods to [BridgeError].
extension BridgeErrorPatterns on BridgeError {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeError_BadStatus value)?  badStatus,TResult Function( BridgeError_Transport value)?  transport,TResult Function( BridgeError_Decode value)?  decode,TResult Function( BridgeError_Create value)?  create,TResult Function( BridgeError_Config value)?  config,TResult Function( BridgeError_RcSlugTaken value)?  rcSlugTaken,TResult Function( BridgeError_RcNotFound value)?  rcNotFound,TResult Function( BridgeError_RcBadRequest value)?  rcBadRequest,TResult Function( BridgeError_RcMissingBinary value)?  rcMissingBinary,TResult Function( BridgeError_RcFailed value)?  rcFailed,TResult Function( BridgeError_TokenAuthExpired value)?  tokenAuthExpired,TResult Function( BridgeError_TokenPinMismatch value)?  tokenPinMismatch,TResult Function( BridgeError_TokenPinMissing value)?  tokenPinMissing,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeError_BadStatus() when badStatus != null:
return badStatus(_that);case BridgeError_Transport() when transport != null:
return transport(_that);case BridgeError_Decode() when decode != null:
return decode(_that);case BridgeError_Create() when create != null:
return create(_that);case BridgeError_Config() when config != null:
return config(_that);case BridgeError_RcSlugTaken() when rcSlugTaken != null:
return rcSlugTaken(_that);case BridgeError_RcNotFound() when rcNotFound != null:
return rcNotFound(_that);case BridgeError_RcBadRequest() when rcBadRequest != null:
return rcBadRequest(_that);case BridgeError_RcMissingBinary() when rcMissingBinary != null:
return rcMissingBinary(_that);case BridgeError_RcFailed() when rcFailed != null:
return rcFailed(_that);case BridgeError_TokenAuthExpired() when tokenAuthExpired != null:
return tokenAuthExpired(_that);case BridgeError_TokenPinMismatch() when tokenPinMismatch != null:
return tokenPinMismatch(_that);case BridgeError_TokenPinMissing() when tokenPinMissing != null:
return tokenPinMissing(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeError_BadStatus value)  badStatus,required TResult Function( BridgeError_Transport value)  transport,required TResult Function( BridgeError_Decode value)  decode,required TResult Function( BridgeError_Create value)  create,required TResult Function( BridgeError_Config value)  config,required TResult Function( BridgeError_RcSlugTaken value)  rcSlugTaken,required TResult Function( BridgeError_RcNotFound value)  rcNotFound,required TResult Function( BridgeError_RcBadRequest value)  rcBadRequest,required TResult Function( BridgeError_RcMissingBinary value)  rcMissingBinary,required TResult Function( BridgeError_RcFailed value)  rcFailed,required TResult Function( BridgeError_TokenAuthExpired value)  tokenAuthExpired,required TResult Function( BridgeError_TokenPinMismatch value)  tokenPinMismatch,required TResult Function( BridgeError_TokenPinMissing value)  tokenPinMissing,}){
final _that = this;
switch (_that) {
case BridgeError_BadStatus():
return badStatus(_that);case BridgeError_Transport():
return transport(_that);case BridgeError_Decode():
return decode(_that);case BridgeError_Create():
return create(_that);case BridgeError_Config():
return config(_that);case BridgeError_RcSlugTaken():
return rcSlugTaken(_that);case BridgeError_RcNotFound():
return rcNotFound(_that);case BridgeError_RcBadRequest():
return rcBadRequest(_that);case BridgeError_RcMissingBinary():
return rcMissingBinary(_that);case BridgeError_RcFailed():
return rcFailed(_that);case BridgeError_TokenAuthExpired():
return tokenAuthExpired(_that);case BridgeError_TokenPinMismatch():
return tokenPinMismatch(_that);case BridgeError_TokenPinMissing():
return tokenPinMissing(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeError_BadStatus value)?  badStatus,TResult? Function( BridgeError_Transport value)?  transport,TResult? Function( BridgeError_Decode value)?  decode,TResult? Function( BridgeError_Create value)?  create,TResult? Function( BridgeError_Config value)?  config,TResult? Function( BridgeError_RcSlugTaken value)?  rcSlugTaken,TResult? Function( BridgeError_RcNotFound value)?  rcNotFound,TResult? Function( BridgeError_RcBadRequest value)?  rcBadRequest,TResult? Function( BridgeError_RcMissingBinary value)?  rcMissingBinary,TResult? Function( BridgeError_RcFailed value)?  rcFailed,TResult? Function( BridgeError_TokenAuthExpired value)?  tokenAuthExpired,TResult? Function( BridgeError_TokenPinMismatch value)?  tokenPinMismatch,TResult? Function( BridgeError_TokenPinMissing value)?  tokenPinMissing,}){
final _that = this;
switch (_that) {
case BridgeError_BadStatus() when badStatus != null:
return badStatus(_that);case BridgeError_Transport() when transport != null:
return transport(_that);case BridgeError_Decode() when decode != null:
return decode(_that);case BridgeError_Create() when create != null:
return create(_that);case BridgeError_Config() when config != null:
return config(_that);case BridgeError_RcSlugTaken() when rcSlugTaken != null:
return rcSlugTaken(_that);case BridgeError_RcNotFound() when rcNotFound != null:
return rcNotFound(_that);case BridgeError_RcBadRequest() when rcBadRequest != null:
return rcBadRequest(_that);case BridgeError_RcMissingBinary() when rcMissingBinary != null:
return rcMissingBinary(_that);case BridgeError_RcFailed() when rcFailed != null:
return rcFailed(_that);case BridgeError_TokenAuthExpired() when tokenAuthExpired != null:
return tokenAuthExpired(_that);case BridgeError_TokenPinMismatch() when tokenPinMismatch != null:
return tokenPinMismatch(_that);case BridgeError_TokenPinMissing() when tokenPinMissing != null:
return tokenPinMissing(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( int code)?  badStatus,TResult Function( String msg)?  transport,TResult Function( String msg)?  decode,TResult Function( String msg)?  create,TResult Function( String msg)?  config,TResult Function( String detail)?  rcSlugTaken,TResult Function( String detail)?  rcNotFound,TResult Function( String detail)?  rcBadRequest,TResult Function()?  rcMissingBinary,TResult Function( String detail)?  rcFailed,TResult Function()?  tokenAuthExpired,TResult Function()?  tokenPinMismatch,TResult Function()?  tokenPinMissing,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeError_BadStatus() when badStatus != null:
return badStatus(_that.code);case BridgeError_Transport() when transport != null:
return transport(_that.msg);case BridgeError_Decode() when decode != null:
return decode(_that.msg);case BridgeError_Create() when create != null:
return create(_that.msg);case BridgeError_Config() when config != null:
return config(_that.msg);case BridgeError_RcSlugTaken() when rcSlugTaken != null:
return rcSlugTaken(_that.detail);case BridgeError_RcNotFound() when rcNotFound != null:
return rcNotFound(_that.detail);case BridgeError_RcBadRequest() when rcBadRequest != null:
return rcBadRequest(_that.detail);case BridgeError_RcMissingBinary() when rcMissingBinary != null:
return rcMissingBinary();case BridgeError_RcFailed() when rcFailed != null:
return rcFailed(_that.detail);case BridgeError_TokenAuthExpired() when tokenAuthExpired != null:
return tokenAuthExpired();case BridgeError_TokenPinMismatch() when tokenPinMismatch != null:
return tokenPinMismatch();case BridgeError_TokenPinMissing() when tokenPinMissing != null:
return tokenPinMissing();case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( int code)  badStatus,required TResult Function( String msg)  transport,required TResult Function( String msg)  decode,required TResult Function( String msg)  create,required TResult Function( String msg)  config,required TResult Function( String detail)  rcSlugTaken,required TResult Function( String detail)  rcNotFound,required TResult Function( String detail)  rcBadRequest,required TResult Function()  rcMissingBinary,required TResult Function( String detail)  rcFailed,required TResult Function()  tokenAuthExpired,required TResult Function()  tokenPinMismatch,required TResult Function()  tokenPinMissing,}) {final _that = this;
switch (_that) {
case BridgeError_BadStatus():
return badStatus(_that.code);case BridgeError_Transport():
return transport(_that.msg);case BridgeError_Decode():
return decode(_that.msg);case BridgeError_Create():
return create(_that.msg);case BridgeError_Config():
return config(_that.msg);case BridgeError_RcSlugTaken():
return rcSlugTaken(_that.detail);case BridgeError_RcNotFound():
return rcNotFound(_that.detail);case BridgeError_RcBadRequest():
return rcBadRequest(_that.detail);case BridgeError_RcMissingBinary():
return rcMissingBinary();case BridgeError_RcFailed():
return rcFailed(_that.detail);case BridgeError_TokenAuthExpired():
return tokenAuthExpired();case BridgeError_TokenPinMismatch():
return tokenPinMismatch();case BridgeError_TokenPinMissing():
return tokenPinMissing();}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( int code)?  badStatus,TResult? Function( String msg)?  transport,TResult? Function( String msg)?  decode,TResult? Function( String msg)?  create,TResult? Function( String msg)?  config,TResult? Function( String detail)?  rcSlugTaken,TResult? Function( String detail)?  rcNotFound,TResult? Function( String detail)?  rcBadRequest,TResult? Function()?  rcMissingBinary,TResult? Function( String detail)?  rcFailed,TResult? Function()?  tokenAuthExpired,TResult? Function()?  tokenPinMismatch,TResult? Function()?  tokenPinMissing,}) {final _that = this;
switch (_that) {
case BridgeError_BadStatus() when badStatus != null:
return badStatus(_that.code);case BridgeError_Transport() when transport != null:
return transport(_that.msg);case BridgeError_Decode() when decode != null:
return decode(_that.msg);case BridgeError_Create() when create != null:
return create(_that.msg);case BridgeError_Config() when config != null:
return config(_that.msg);case BridgeError_RcSlugTaken() when rcSlugTaken != null:
return rcSlugTaken(_that.detail);case BridgeError_RcNotFound() when rcNotFound != null:
return rcNotFound(_that.detail);case BridgeError_RcBadRequest() when rcBadRequest != null:
return rcBadRequest(_that.detail);case BridgeError_RcMissingBinary() when rcMissingBinary != null:
return rcMissingBinary();case BridgeError_RcFailed() when rcFailed != null:
return rcFailed(_that.detail);case BridgeError_TokenAuthExpired() when tokenAuthExpired != null:
return tokenAuthExpired();case BridgeError_TokenPinMismatch() when tokenPinMismatch != null:
return tokenPinMismatch();case BridgeError_TokenPinMissing() when tokenPinMissing != null:
return tokenPinMissing();case _:
  return null;

}
}

}

/// @nodoc


class BridgeError_BadStatus extends BridgeError {
  const BridgeError_BadStatus({required this.code}): super._();
  

 final  int code;

/// Create a copy of BridgeError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeError_BadStatusCopyWith<BridgeError_BadStatus> get copyWith => _$BridgeError_BadStatusCopyWithImpl<BridgeError_BadStatus>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeError_BadStatus&&(identical(other.code, code) || other.code == code));
}


@override
int get hashCode => Object.hash(runtimeType,code);

@override
String toString() {
  return 'BridgeError.badStatus(code: $code)';
}


}

/// @nodoc
abstract mixin class $BridgeError_BadStatusCopyWith<$Res> implements $BridgeErrorCopyWith<$Res> {
  factory $BridgeError_BadStatusCopyWith(BridgeError_BadStatus value, $Res Function(BridgeError_BadStatus) _then) = _$BridgeError_BadStatusCopyWithImpl;
@useResult
$Res call({
 int code
});




}
/// @nodoc
class _$BridgeError_BadStatusCopyWithImpl<$Res>
    implements $BridgeError_BadStatusCopyWith<$Res> {
  _$BridgeError_BadStatusCopyWithImpl(this._self, this._then);

  final BridgeError_BadStatus _self;
  final $Res Function(BridgeError_BadStatus) _then;

/// Create a copy of BridgeError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? code = null,}) {
  return _then(BridgeError_BadStatus(
code: null == code ? _self.code : code // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class BridgeError_Transport extends BridgeError {
  const BridgeError_Transport({required this.msg}): super._();
  

 final  String msg;

/// Create a copy of BridgeError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeError_TransportCopyWith<BridgeError_Transport> get copyWith => _$BridgeError_TransportCopyWithImpl<BridgeError_Transport>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeError_Transport&&(identical(other.msg, msg) || other.msg == msg));
}


@override
int get hashCode => Object.hash(runtimeType,msg);

@override
String toString() {
  return 'BridgeError.transport(msg: $msg)';
}


}

/// @nodoc
abstract mixin class $BridgeError_TransportCopyWith<$Res> implements $BridgeErrorCopyWith<$Res> {
  factory $BridgeError_TransportCopyWith(BridgeError_Transport value, $Res Function(BridgeError_Transport) _then) = _$BridgeError_TransportCopyWithImpl;
@useResult
$Res call({
 String msg
});




}
/// @nodoc
class _$BridgeError_TransportCopyWithImpl<$Res>
    implements $BridgeError_TransportCopyWith<$Res> {
  _$BridgeError_TransportCopyWithImpl(this._self, this._then);

  final BridgeError_Transport _self;
  final $Res Function(BridgeError_Transport) _then;

/// Create a copy of BridgeError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? msg = null,}) {
  return _then(BridgeError_Transport(
msg: null == msg ? _self.msg : msg // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class BridgeError_Decode extends BridgeError {
  const BridgeError_Decode({required this.msg}): super._();
  

 final  String msg;

/// Create a copy of BridgeError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeError_DecodeCopyWith<BridgeError_Decode> get copyWith => _$BridgeError_DecodeCopyWithImpl<BridgeError_Decode>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeError_Decode&&(identical(other.msg, msg) || other.msg == msg));
}


@override
int get hashCode => Object.hash(runtimeType,msg);

@override
String toString() {
  return 'BridgeError.decode(msg: $msg)';
}


}

/// @nodoc
abstract mixin class $BridgeError_DecodeCopyWith<$Res> implements $BridgeErrorCopyWith<$Res> {
  factory $BridgeError_DecodeCopyWith(BridgeError_Decode value, $Res Function(BridgeError_Decode) _then) = _$BridgeError_DecodeCopyWithImpl;
@useResult
$Res call({
 String msg
});




}
/// @nodoc
class _$BridgeError_DecodeCopyWithImpl<$Res>
    implements $BridgeError_DecodeCopyWith<$Res> {
  _$BridgeError_DecodeCopyWithImpl(this._self, this._then);

  final BridgeError_Decode _self;
  final $Res Function(BridgeError_Decode) _then;

/// Create a copy of BridgeError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? msg = null,}) {
  return _then(BridgeError_Decode(
msg: null == msg ? _self.msg : msg // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class BridgeError_Create extends BridgeError {
  const BridgeError_Create({required this.msg}): super._();
  

 final  String msg;

/// Create a copy of BridgeError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeError_CreateCopyWith<BridgeError_Create> get copyWith => _$BridgeError_CreateCopyWithImpl<BridgeError_Create>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeError_Create&&(identical(other.msg, msg) || other.msg == msg));
}


@override
int get hashCode => Object.hash(runtimeType,msg);

@override
String toString() {
  return 'BridgeError.create(msg: $msg)';
}


}

/// @nodoc
abstract mixin class $BridgeError_CreateCopyWith<$Res> implements $BridgeErrorCopyWith<$Res> {
  factory $BridgeError_CreateCopyWith(BridgeError_Create value, $Res Function(BridgeError_Create) _then) = _$BridgeError_CreateCopyWithImpl;
@useResult
$Res call({
 String msg
});




}
/// @nodoc
class _$BridgeError_CreateCopyWithImpl<$Res>
    implements $BridgeError_CreateCopyWith<$Res> {
  _$BridgeError_CreateCopyWithImpl(this._self, this._then);

  final BridgeError_Create _self;
  final $Res Function(BridgeError_Create) _then;

/// Create a copy of BridgeError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? msg = null,}) {
  return _then(BridgeError_Create(
msg: null == msg ? _self.msg : msg // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class BridgeError_Config extends BridgeError {
  const BridgeError_Config({required this.msg}): super._();
  

 final  String msg;

/// Create a copy of BridgeError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeError_ConfigCopyWith<BridgeError_Config> get copyWith => _$BridgeError_ConfigCopyWithImpl<BridgeError_Config>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeError_Config&&(identical(other.msg, msg) || other.msg == msg));
}


@override
int get hashCode => Object.hash(runtimeType,msg);

@override
String toString() {
  return 'BridgeError.config(msg: $msg)';
}


}

/// @nodoc
abstract mixin class $BridgeError_ConfigCopyWith<$Res> implements $BridgeErrorCopyWith<$Res> {
  factory $BridgeError_ConfigCopyWith(BridgeError_Config value, $Res Function(BridgeError_Config) _then) = _$BridgeError_ConfigCopyWithImpl;
@useResult
$Res call({
 String msg
});




}
/// @nodoc
class _$BridgeError_ConfigCopyWithImpl<$Res>
    implements $BridgeError_ConfigCopyWith<$Res> {
  _$BridgeError_ConfigCopyWithImpl(this._self, this._then);

  final BridgeError_Config _self;
  final $Res Function(BridgeError_Config) _then;

/// Create a copy of BridgeError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? msg = null,}) {
  return _then(BridgeError_Config(
msg: null == msg ? _self.msg : msg // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class BridgeError_RcSlugTaken extends BridgeError {
  const BridgeError_RcSlugTaken({required this.detail}): super._();
  

 final  String detail;

/// Create a copy of BridgeError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeError_RcSlugTakenCopyWith<BridgeError_RcSlugTaken> get copyWith => _$BridgeError_RcSlugTakenCopyWithImpl<BridgeError_RcSlugTaken>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeError_RcSlugTaken&&(identical(other.detail, detail) || other.detail == detail));
}


@override
int get hashCode => Object.hash(runtimeType,detail);

@override
String toString() {
  return 'BridgeError.rcSlugTaken(detail: $detail)';
}


}

/// @nodoc
abstract mixin class $BridgeError_RcSlugTakenCopyWith<$Res> implements $BridgeErrorCopyWith<$Res> {
  factory $BridgeError_RcSlugTakenCopyWith(BridgeError_RcSlugTaken value, $Res Function(BridgeError_RcSlugTaken) _then) = _$BridgeError_RcSlugTakenCopyWithImpl;
@useResult
$Res call({
 String detail
});




}
/// @nodoc
class _$BridgeError_RcSlugTakenCopyWithImpl<$Res>
    implements $BridgeError_RcSlugTakenCopyWith<$Res> {
  _$BridgeError_RcSlugTakenCopyWithImpl(this._self, this._then);

  final BridgeError_RcSlugTaken _self;
  final $Res Function(BridgeError_RcSlugTaken) _then;

/// Create a copy of BridgeError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? detail = null,}) {
  return _then(BridgeError_RcSlugTaken(
detail: null == detail ? _self.detail : detail // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class BridgeError_RcNotFound extends BridgeError {
  const BridgeError_RcNotFound({required this.detail}): super._();
  

 final  String detail;

/// Create a copy of BridgeError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeError_RcNotFoundCopyWith<BridgeError_RcNotFound> get copyWith => _$BridgeError_RcNotFoundCopyWithImpl<BridgeError_RcNotFound>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeError_RcNotFound&&(identical(other.detail, detail) || other.detail == detail));
}


@override
int get hashCode => Object.hash(runtimeType,detail);

@override
String toString() {
  return 'BridgeError.rcNotFound(detail: $detail)';
}


}

/// @nodoc
abstract mixin class $BridgeError_RcNotFoundCopyWith<$Res> implements $BridgeErrorCopyWith<$Res> {
  factory $BridgeError_RcNotFoundCopyWith(BridgeError_RcNotFound value, $Res Function(BridgeError_RcNotFound) _then) = _$BridgeError_RcNotFoundCopyWithImpl;
@useResult
$Res call({
 String detail
});




}
/// @nodoc
class _$BridgeError_RcNotFoundCopyWithImpl<$Res>
    implements $BridgeError_RcNotFoundCopyWith<$Res> {
  _$BridgeError_RcNotFoundCopyWithImpl(this._self, this._then);

  final BridgeError_RcNotFound _self;
  final $Res Function(BridgeError_RcNotFound) _then;

/// Create a copy of BridgeError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? detail = null,}) {
  return _then(BridgeError_RcNotFound(
detail: null == detail ? _self.detail : detail // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class BridgeError_RcBadRequest extends BridgeError {
  const BridgeError_RcBadRequest({required this.detail}): super._();
  

 final  String detail;

/// Create a copy of BridgeError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeError_RcBadRequestCopyWith<BridgeError_RcBadRequest> get copyWith => _$BridgeError_RcBadRequestCopyWithImpl<BridgeError_RcBadRequest>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeError_RcBadRequest&&(identical(other.detail, detail) || other.detail == detail));
}


@override
int get hashCode => Object.hash(runtimeType,detail);

@override
String toString() {
  return 'BridgeError.rcBadRequest(detail: $detail)';
}


}

/// @nodoc
abstract mixin class $BridgeError_RcBadRequestCopyWith<$Res> implements $BridgeErrorCopyWith<$Res> {
  factory $BridgeError_RcBadRequestCopyWith(BridgeError_RcBadRequest value, $Res Function(BridgeError_RcBadRequest) _then) = _$BridgeError_RcBadRequestCopyWithImpl;
@useResult
$Res call({
 String detail
});




}
/// @nodoc
class _$BridgeError_RcBadRequestCopyWithImpl<$Res>
    implements $BridgeError_RcBadRequestCopyWith<$Res> {
  _$BridgeError_RcBadRequestCopyWithImpl(this._self, this._then);

  final BridgeError_RcBadRequest _self;
  final $Res Function(BridgeError_RcBadRequest) _then;

/// Create a copy of BridgeError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? detail = null,}) {
  return _then(BridgeError_RcBadRequest(
detail: null == detail ? _self.detail : detail // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class BridgeError_RcMissingBinary extends BridgeError {
  const BridgeError_RcMissingBinary(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeError_RcMissingBinary);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'BridgeError.rcMissingBinary()';
}


}




/// @nodoc


class BridgeError_RcFailed extends BridgeError {
  const BridgeError_RcFailed({required this.detail}): super._();
  

 final  String detail;

/// Create a copy of BridgeError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeError_RcFailedCopyWith<BridgeError_RcFailed> get copyWith => _$BridgeError_RcFailedCopyWithImpl<BridgeError_RcFailed>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeError_RcFailed&&(identical(other.detail, detail) || other.detail == detail));
}


@override
int get hashCode => Object.hash(runtimeType,detail);

@override
String toString() {
  return 'BridgeError.rcFailed(detail: $detail)';
}


}

/// @nodoc
abstract mixin class $BridgeError_RcFailedCopyWith<$Res> implements $BridgeErrorCopyWith<$Res> {
  factory $BridgeError_RcFailedCopyWith(BridgeError_RcFailed value, $Res Function(BridgeError_RcFailed) _then) = _$BridgeError_RcFailedCopyWithImpl;
@useResult
$Res call({
 String detail
});




}
/// @nodoc
class _$BridgeError_RcFailedCopyWithImpl<$Res>
    implements $BridgeError_RcFailedCopyWith<$Res> {
  _$BridgeError_RcFailedCopyWithImpl(this._self, this._then);

  final BridgeError_RcFailed _self;
  final $Res Function(BridgeError_RcFailed) _then;

/// Create a copy of BridgeError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? detail = null,}) {
  return _then(BridgeError_RcFailed(
detail: null == detail ? _self.detail : detail // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class BridgeError_TokenAuthExpired extends BridgeError {
  const BridgeError_TokenAuthExpired(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeError_TokenAuthExpired);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'BridgeError.tokenAuthExpired()';
}


}




/// @nodoc


class BridgeError_TokenPinMismatch extends BridgeError {
  const BridgeError_TokenPinMismatch(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeError_TokenPinMismatch);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'BridgeError.tokenPinMismatch()';
}


}




/// @nodoc


class BridgeError_TokenPinMissing extends BridgeError {
  const BridgeError_TokenPinMissing(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeError_TokenPinMissing);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'BridgeError.tokenPinMissing()';
}


}




// dart format on

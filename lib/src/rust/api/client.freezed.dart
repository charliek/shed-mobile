// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'client.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$BridgeCredentialEvent {

 String get server;/// `"token"` or `"mtls"`.
 String get authMode;
/// Create a copy of BridgeCredentialEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeCredentialEventCopyWith<BridgeCredentialEvent> get copyWith => _$BridgeCredentialEventCopyWithImpl<BridgeCredentialEvent>(this as BridgeCredentialEvent, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeCredentialEvent&&(identical(other.server, server) || other.server == server)&&(identical(other.authMode, authMode) || other.authMode == authMode));
}


@override
int get hashCode => Object.hash(runtimeType,server,authMode);

@override
String toString() {
  return 'BridgeCredentialEvent(server: $server, authMode: $authMode)';
}


}

/// @nodoc
abstract mixin class $BridgeCredentialEventCopyWith<$Res>  {
  factory $BridgeCredentialEventCopyWith(BridgeCredentialEvent value, $Res Function(BridgeCredentialEvent) _then) = _$BridgeCredentialEventCopyWithImpl;
@useResult
$Res call({
 String server, String authMode
});




}
/// @nodoc
class _$BridgeCredentialEventCopyWithImpl<$Res>
    implements $BridgeCredentialEventCopyWith<$Res> {
  _$BridgeCredentialEventCopyWithImpl(this._self, this._then);

  final BridgeCredentialEvent _self;
  final $Res Function(BridgeCredentialEvent) _then;

/// Create a copy of BridgeCredentialEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? server = null,Object? authMode = null,}) {
  return _then(_self.copyWith(
server: null == server ? _self.server : server // ignore: cast_nullable_to_non_nullable
as String,authMode: null == authMode ? _self.authMode : authMode // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [BridgeCredentialEvent].
extension BridgeCredentialEventPatterns on BridgeCredentialEvent {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeCredentialEvent_Adopted value)?  adopted,TResult Function( BridgeCredentialEvent_ModeChanged value)?  modeChanged,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeCredentialEvent_Adopted() when adopted != null:
return adopted(_that);case BridgeCredentialEvent_ModeChanged() when modeChanged != null:
return modeChanged(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeCredentialEvent_Adopted value)  adopted,required TResult Function( BridgeCredentialEvent_ModeChanged value)  modeChanged,}){
final _that = this;
switch (_that) {
case BridgeCredentialEvent_Adopted():
return adopted(_that);case BridgeCredentialEvent_ModeChanged():
return modeChanged(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeCredentialEvent_Adopted value)?  adopted,TResult? Function( BridgeCredentialEvent_ModeChanged value)?  modeChanged,}){
final _that = this;
switch (_that) {
case BridgeCredentialEvent_Adopted() when adopted != null:
return adopted(_that);case BridgeCredentialEvent_ModeChanged() when modeChanged != null:
return modeChanged(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String server,  String authMode,  BigInt? expiresAtUnix)?  adopted,TResult Function( String server,  String authMode)?  modeChanged,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeCredentialEvent_Adopted() when adopted != null:
return adopted(_that.server,_that.authMode,_that.expiresAtUnix);case BridgeCredentialEvent_ModeChanged() when modeChanged != null:
return modeChanged(_that.server,_that.authMode);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String server,  String authMode,  BigInt? expiresAtUnix)  adopted,required TResult Function( String server,  String authMode)  modeChanged,}) {final _that = this;
switch (_that) {
case BridgeCredentialEvent_Adopted():
return adopted(_that.server,_that.authMode,_that.expiresAtUnix);case BridgeCredentialEvent_ModeChanged():
return modeChanged(_that.server,_that.authMode);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String server,  String authMode,  BigInt? expiresAtUnix)?  adopted,TResult? Function( String server,  String authMode)?  modeChanged,}) {final _that = this;
switch (_that) {
case BridgeCredentialEvent_Adopted() when adopted != null:
return adopted(_that.server,_that.authMode,_that.expiresAtUnix);case BridgeCredentialEvent_ModeChanged() when modeChanged != null:
return modeChanged(_that.server,_that.authMode);case _:
  return null;

}
}

}

/// @nodoc


class BridgeCredentialEvent_Adopted extends BridgeCredentialEvent {
  const BridgeCredentialEvent_Adopted({required this.server, required this.authMode, this.expiresAtUnix}): super._();
  

@override final  String server;
/// `"token"` or `"mtls"`.
@override final  String authMode;
 final  BigInt? expiresAtUnix;

/// Create a copy of BridgeCredentialEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeCredentialEvent_AdoptedCopyWith<BridgeCredentialEvent_Adopted> get copyWith => _$BridgeCredentialEvent_AdoptedCopyWithImpl<BridgeCredentialEvent_Adopted>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeCredentialEvent_Adopted&&(identical(other.server, server) || other.server == server)&&(identical(other.authMode, authMode) || other.authMode == authMode)&&(identical(other.expiresAtUnix, expiresAtUnix) || other.expiresAtUnix == expiresAtUnix));
}


@override
int get hashCode => Object.hash(runtimeType,server,authMode,expiresAtUnix);

@override
String toString() {
  return 'BridgeCredentialEvent.adopted(server: $server, authMode: $authMode, expiresAtUnix: $expiresAtUnix)';
}


}

/// @nodoc
abstract mixin class $BridgeCredentialEvent_AdoptedCopyWith<$Res> implements $BridgeCredentialEventCopyWith<$Res> {
  factory $BridgeCredentialEvent_AdoptedCopyWith(BridgeCredentialEvent_Adopted value, $Res Function(BridgeCredentialEvent_Adopted) _then) = _$BridgeCredentialEvent_AdoptedCopyWithImpl;
@override @useResult
$Res call({
 String server, String authMode, BigInt? expiresAtUnix
});




}
/// @nodoc
class _$BridgeCredentialEvent_AdoptedCopyWithImpl<$Res>
    implements $BridgeCredentialEvent_AdoptedCopyWith<$Res> {
  _$BridgeCredentialEvent_AdoptedCopyWithImpl(this._self, this._then);

  final BridgeCredentialEvent_Adopted _self;
  final $Res Function(BridgeCredentialEvent_Adopted) _then;

/// Create a copy of BridgeCredentialEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? server = null,Object? authMode = null,Object? expiresAtUnix = freezed,}) {
  return _then(BridgeCredentialEvent_Adopted(
server: null == server ? _self.server : server // ignore: cast_nullable_to_non_nullable
as String,authMode: null == authMode ? _self.authMode : authMode // ignore: cast_nullable_to_non_nullable
as String,expiresAtUnix: freezed == expiresAtUnix ? _self.expiresAtUnix : expiresAtUnix // ignore: cast_nullable_to_non_nullable
as BigInt?,
  ));
}


}

/// @nodoc


class BridgeCredentialEvent_ModeChanged extends BridgeCredentialEvent {
  const BridgeCredentialEvent_ModeChanged({required this.server, required this.authMode}): super._();
  

@override final  String server;
@override final  String authMode;

/// Create a copy of BridgeCredentialEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeCredentialEvent_ModeChangedCopyWith<BridgeCredentialEvent_ModeChanged> get copyWith => _$BridgeCredentialEvent_ModeChangedCopyWithImpl<BridgeCredentialEvent_ModeChanged>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeCredentialEvent_ModeChanged&&(identical(other.server, server) || other.server == server)&&(identical(other.authMode, authMode) || other.authMode == authMode));
}


@override
int get hashCode => Object.hash(runtimeType,server,authMode);

@override
String toString() {
  return 'BridgeCredentialEvent.modeChanged(server: $server, authMode: $authMode)';
}


}

/// @nodoc
abstract mixin class $BridgeCredentialEvent_ModeChangedCopyWith<$Res> implements $BridgeCredentialEventCopyWith<$Res> {
  factory $BridgeCredentialEvent_ModeChangedCopyWith(BridgeCredentialEvent_ModeChanged value, $Res Function(BridgeCredentialEvent_ModeChanged) _then) = _$BridgeCredentialEvent_ModeChangedCopyWithImpl;
@override @useResult
$Res call({
 String server, String authMode
});




}
/// @nodoc
class _$BridgeCredentialEvent_ModeChangedCopyWithImpl<$Res>
    implements $BridgeCredentialEvent_ModeChangedCopyWith<$Res> {
  _$BridgeCredentialEvent_ModeChangedCopyWithImpl(this._self, this._then);

  final BridgeCredentialEvent_ModeChanged _self;
  final $Res Function(BridgeCredentialEvent_ModeChanged) _then;

/// Create a copy of BridgeCredentialEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? server = null,Object? authMode = null,}) {
  return _then(BridgeCredentialEvent_ModeChanged(
server: null == server ? _self.server : server // ignore: cast_nullable_to_non_nullable
as String,authMode: null == authMode ? _self.authMode : authMode // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on

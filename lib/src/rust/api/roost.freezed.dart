// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'roost.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$BridgeRoostUpdate {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeRoostUpdate);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'BridgeRoostUpdate()';
}


}

/// @nodoc
class $BridgeRoostUpdateCopyWith<$Res>  {
$BridgeRoostUpdateCopyWith(BridgeRoostUpdate _, $Res Function(BridgeRoostUpdate) __);
}


/// Adds pattern-matching-related methods to [BridgeRoostUpdate].
extension BridgeRoostUpdatePatterns on BridgeRoostUpdate {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeRoostUpdate_Snapshot value)?  snapshot,TResult Function( BridgeRoostUpdate_Down value)?  down,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeRoostUpdate_Snapshot() when snapshot != null:
return snapshot(_that);case BridgeRoostUpdate_Down() when down != null:
return down(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeRoostUpdate_Snapshot value)  snapshot,required TResult Function( BridgeRoostUpdate_Down value)  down,}){
final _that = this;
switch (_that) {
case BridgeRoostUpdate_Snapshot():
return snapshot(_that);case BridgeRoostUpdate_Down():
return down(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeRoostUpdate_Snapshot value)?  snapshot,TResult? Function( BridgeRoostUpdate_Down value)?  down,}){
final _that = this;
switch (_that) {
case BridgeRoostUpdate_Snapshot() when snapshot != null:
return snapshot(_that);case BridgeRoostUpdate_Down() when down != null:
return down(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( List<BridgeRcSession> sessions,  BigInt? revision)?  snapshot,TResult Function( String reason)?  down,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeRoostUpdate_Snapshot() when snapshot != null:
return snapshot(_that.sessions,_that.revision);case BridgeRoostUpdate_Down() when down != null:
return down(_that.reason);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( List<BridgeRcSession> sessions,  BigInt? revision)  snapshot,required TResult Function( String reason)  down,}) {final _that = this;
switch (_that) {
case BridgeRoostUpdate_Snapshot():
return snapshot(_that.sessions,_that.revision);case BridgeRoostUpdate_Down():
return down(_that.reason);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( List<BridgeRcSession> sessions,  BigInt? revision)?  snapshot,TResult? Function( String reason)?  down,}) {final _that = this;
switch (_that) {
case BridgeRoostUpdate_Snapshot() when snapshot != null:
return snapshot(_that.sessions,_that.revision);case BridgeRoostUpdate_Down() when down != null:
return down(_that.reason);case _:
  return null;

}
}

}

/// @nodoc


class BridgeRoostUpdate_Snapshot extends BridgeRoostUpdate {
  const BridgeRoostUpdate_Snapshot({required final  List<BridgeRcSession> sessions, this.revision}): _sessions = sessions,super._();
  

 final  List<BridgeRcSession> _sessions;
 List<BridgeRcSession> get sessions {
  if (_sessions is EqualUnmodifiableListView) return _sessions;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_sessions);
}

 final  BigInt? revision;

/// Create a copy of BridgeRoostUpdate
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeRoostUpdate_SnapshotCopyWith<BridgeRoostUpdate_Snapshot> get copyWith => _$BridgeRoostUpdate_SnapshotCopyWithImpl<BridgeRoostUpdate_Snapshot>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeRoostUpdate_Snapshot&&const DeepCollectionEquality().equals(other._sessions, _sessions)&&(identical(other.revision, revision) || other.revision == revision));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(_sessions),revision);

@override
String toString() {
  return 'BridgeRoostUpdate.snapshot(sessions: $sessions, revision: $revision)';
}


}

/// @nodoc
abstract mixin class $BridgeRoostUpdate_SnapshotCopyWith<$Res> implements $BridgeRoostUpdateCopyWith<$Res> {
  factory $BridgeRoostUpdate_SnapshotCopyWith(BridgeRoostUpdate_Snapshot value, $Res Function(BridgeRoostUpdate_Snapshot) _then) = _$BridgeRoostUpdate_SnapshotCopyWithImpl;
@useResult
$Res call({
 List<BridgeRcSession> sessions, BigInt? revision
});




}
/// @nodoc
class _$BridgeRoostUpdate_SnapshotCopyWithImpl<$Res>
    implements $BridgeRoostUpdate_SnapshotCopyWith<$Res> {
  _$BridgeRoostUpdate_SnapshotCopyWithImpl(this._self, this._then);

  final BridgeRoostUpdate_Snapshot _self;
  final $Res Function(BridgeRoostUpdate_Snapshot) _then;

/// Create a copy of BridgeRoostUpdate
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? sessions = null,Object? revision = freezed,}) {
  return _then(BridgeRoostUpdate_Snapshot(
sessions: null == sessions ? _self._sessions : sessions // ignore: cast_nullable_to_non_nullable
as List<BridgeRcSession>,revision: freezed == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as BigInt?,
  ));
}


}

/// @nodoc


class BridgeRoostUpdate_Down extends BridgeRoostUpdate {
  const BridgeRoostUpdate_Down({required this.reason}): super._();
  

 final  String reason;

/// Create a copy of BridgeRoostUpdate
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeRoostUpdate_DownCopyWith<BridgeRoostUpdate_Down> get copyWith => _$BridgeRoostUpdate_DownCopyWithImpl<BridgeRoostUpdate_Down>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeRoostUpdate_Down&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode => Object.hash(runtimeType,reason);

@override
String toString() {
  return 'BridgeRoostUpdate.down(reason: $reason)';
}


}

/// @nodoc
abstract mixin class $BridgeRoostUpdate_DownCopyWith<$Res> implements $BridgeRoostUpdateCopyWith<$Res> {
  factory $BridgeRoostUpdate_DownCopyWith(BridgeRoostUpdate_Down value, $Res Function(BridgeRoostUpdate_Down) _then) = _$BridgeRoostUpdate_DownCopyWithImpl;
@useResult
$Res call({
 String reason
});




}
/// @nodoc
class _$BridgeRoostUpdate_DownCopyWithImpl<$Res>
    implements $BridgeRoostUpdate_DownCopyWith<$Res> {
  _$BridgeRoostUpdate_DownCopyWithImpl(this._self, this._then);

  final BridgeRoostUpdate_Down _self;
  final $Res Function(BridgeRoostUpdate_Down) _then;

/// Create a copy of BridgeRoostUpdate
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? reason = null,}) {
  return _then(BridgeRoostUpdate_Down(
reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on

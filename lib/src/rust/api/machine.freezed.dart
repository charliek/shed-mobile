// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'machine.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$BridgeMachineUpdate {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeMachineUpdate);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'BridgeMachineUpdate()';
}


}

/// @nodoc
class $BridgeMachineUpdateCopyWith<$Res>  {
$BridgeMachineUpdateCopyWith(BridgeMachineUpdate _, $Res Function(BridgeMachineUpdate) __);
}


/// Adds pattern-matching-related methods to [BridgeMachineUpdate].
extension BridgeMachineUpdatePatterns on BridgeMachineUpdate {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeMachineUpdate_Snapshot value)?  snapshot,TResult Function( BridgeMachineUpdate_Event value)?  event,TResult Function( BridgeMachineUpdate_Down value)?  down,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeMachineUpdate_Snapshot() when snapshot != null:
return snapshot(_that);case BridgeMachineUpdate_Event() when event != null:
return event(_that);case BridgeMachineUpdate_Down() when down != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeMachineUpdate_Snapshot value)  snapshot,required TResult Function( BridgeMachineUpdate_Event value)  event,required TResult Function( BridgeMachineUpdate_Down value)  down,}){
final _that = this;
switch (_that) {
case BridgeMachineUpdate_Snapshot():
return snapshot(_that);case BridgeMachineUpdate_Event():
return event(_that);case BridgeMachineUpdate_Down():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeMachineUpdate_Snapshot value)?  snapshot,TResult? Function( BridgeMachineUpdate_Event value)?  event,TResult? Function( BridgeMachineUpdate_Down value)?  down,}){
final _that = this;
switch (_that) {
case BridgeMachineUpdate_Snapshot() when snapshot != null:
return snapshot(_that);case BridgeMachineUpdate_Event() when event != null:
return event(_that);case BridgeMachineUpdate_Down() when down != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( List<BridgeRcSession> sessions)?  snapshot,TResult Function( BridgeRcEvent event)?  event,TResult Function( String reason)?  down,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeMachineUpdate_Snapshot() when snapshot != null:
return snapshot(_that.sessions);case BridgeMachineUpdate_Event() when event != null:
return event(_that.event);case BridgeMachineUpdate_Down() when down != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( List<BridgeRcSession> sessions)  snapshot,required TResult Function( BridgeRcEvent event)  event,required TResult Function( String reason)  down,}) {final _that = this;
switch (_that) {
case BridgeMachineUpdate_Snapshot():
return snapshot(_that.sessions);case BridgeMachineUpdate_Event():
return event(_that.event);case BridgeMachineUpdate_Down():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( List<BridgeRcSession> sessions)?  snapshot,TResult? Function( BridgeRcEvent event)?  event,TResult? Function( String reason)?  down,}) {final _that = this;
switch (_that) {
case BridgeMachineUpdate_Snapshot() when snapshot != null:
return snapshot(_that.sessions);case BridgeMachineUpdate_Event() when event != null:
return event(_that.event);case BridgeMachineUpdate_Down() when down != null:
return down(_that.reason);case _:
  return null;

}
}

}

/// @nodoc


class BridgeMachineUpdate_Snapshot extends BridgeMachineUpdate {
  const BridgeMachineUpdate_Snapshot({required final  List<BridgeRcSession> sessions}): _sessions = sessions,super._();
  

 final  List<BridgeRcSession> _sessions;
 List<BridgeRcSession> get sessions {
  if (_sessions is EqualUnmodifiableListView) return _sessions;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_sessions);
}


/// Create a copy of BridgeMachineUpdate
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeMachineUpdate_SnapshotCopyWith<BridgeMachineUpdate_Snapshot> get copyWith => _$BridgeMachineUpdate_SnapshotCopyWithImpl<BridgeMachineUpdate_Snapshot>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeMachineUpdate_Snapshot&&const DeepCollectionEquality().equals(other._sessions, _sessions));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(_sessions));

@override
String toString() {
  return 'BridgeMachineUpdate.snapshot(sessions: $sessions)';
}


}

/// @nodoc
abstract mixin class $BridgeMachineUpdate_SnapshotCopyWith<$Res> implements $BridgeMachineUpdateCopyWith<$Res> {
  factory $BridgeMachineUpdate_SnapshotCopyWith(BridgeMachineUpdate_Snapshot value, $Res Function(BridgeMachineUpdate_Snapshot) _then) = _$BridgeMachineUpdate_SnapshotCopyWithImpl;
@useResult
$Res call({
 List<BridgeRcSession> sessions
});




}
/// @nodoc
class _$BridgeMachineUpdate_SnapshotCopyWithImpl<$Res>
    implements $BridgeMachineUpdate_SnapshotCopyWith<$Res> {
  _$BridgeMachineUpdate_SnapshotCopyWithImpl(this._self, this._then);

  final BridgeMachineUpdate_Snapshot _self;
  final $Res Function(BridgeMachineUpdate_Snapshot) _then;

/// Create a copy of BridgeMachineUpdate
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? sessions = null,}) {
  return _then(BridgeMachineUpdate_Snapshot(
sessions: null == sessions ? _self._sessions : sessions // ignore: cast_nullable_to_non_nullable
as List<BridgeRcSession>,
  ));
}


}

/// @nodoc


class BridgeMachineUpdate_Event extends BridgeMachineUpdate {
  const BridgeMachineUpdate_Event({required this.event}): super._();
  

 final  BridgeRcEvent event;

/// Create a copy of BridgeMachineUpdate
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeMachineUpdate_EventCopyWith<BridgeMachineUpdate_Event> get copyWith => _$BridgeMachineUpdate_EventCopyWithImpl<BridgeMachineUpdate_Event>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeMachineUpdate_Event&&(identical(other.event, event) || other.event == event));
}


@override
int get hashCode => Object.hash(runtimeType,event);

@override
String toString() {
  return 'BridgeMachineUpdate.event(event: $event)';
}


}

/// @nodoc
abstract mixin class $BridgeMachineUpdate_EventCopyWith<$Res> implements $BridgeMachineUpdateCopyWith<$Res> {
  factory $BridgeMachineUpdate_EventCopyWith(BridgeMachineUpdate_Event value, $Res Function(BridgeMachineUpdate_Event) _then) = _$BridgeMachineUpdate_EventCopyWithImpl;
@useResult
$Res call({
 BridgeRcEvent event
});


$BridgeRcEventCopyWith<$Res> get event;

}
/// @nodoc
class _$BridgeMachineUpdate_EventCopyWithImpl<$Res>
    implements $BridgeMachineUpdate_EventCopyWith<$Res> {
  _$BridgeMachineUpdate_EventCopyWithImpl(this._self, this._then);

  final BridgeMachineUpdate_Event _self;
  final $Res Function(BridgeMachineUpdate_Event) _then;

/// Create a copy of BridgeMachineUpdate
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? event = null,}) {
  return _then(BridgeMachineUpdate_Event(
event: null == event ? _self.event : event // ignore: cast_nullable_to_non_nullable
as BridgeRcEvent,
  ));
}

/// Create a copy of BridgeMachineUpdate
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BridgeRcEventCopyWith<$Res> get event {
  
  return $BridgeRcEventCopyWith<$Res>(_self.event, (value) {
    return _then(_self.copyWith(event: value));
  });
}
}

/// @nodoc


class BridgeMachineUpdate_Down extends BridgeMachineUpdate {
  const BridgeMachineUpdate_Down({required this.reason}): super._();
  

 final  String reason;

/// Create a copy of BridgeMachineUpdate
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeMachineUpdate_DownCopyWith<BridgeMachineUpdate_Down> get copyWith => _$BridgeMachineUpdate_DownCopyWithImpl<BridgeMachineUpdate_Down>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeMachineUpdate_Down&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode => Object.hash(runtimeType,reason);

@override
String toString() {
  return 'BridgeMachineUpdate.down(reason: $reason)';
}


}

/// @nodoc
abstract mixin class $BridgeMachineUpdate_DownCopyWith<$Res> implements $BridgeMachineUpdateCopyWith<$Res> {
  factory $BridgeMachineUpdate_DownCopyWith(BridgeMachineUpdate_Down value, $Res Function(BridgeMachineUpdate_Down) _then) = _$BridgeMachineUpdate_DownCopyWithImpl;
@useResult
$Res call({
 String reason
});




}
/// @nodoc
class _$BridgeMachineUpdate_DownCopyWithImpl<$Res>
    implements $BridgeMachineUpdate_DownCopyWith<$Res> {
  _$BridgeMachineUpdate_DownCopyWithImpl(this._self, this._then);

  final BridgeMachineUpdate_Down _self;
  final $Res Function(BridgeMachineUpdate_Down) _then;

/// Create a copy of BridgeMachineUpdate
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? reason = null,}) {
  return _then(BridgeMachineUpdate_Down(
reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on

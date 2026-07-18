// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'watcher.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$BridgeWatcherUpdate {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeWatcherUpdate);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'BridgeWatcherUpdate()';
}


}

/// @nodoc
class $BridgeWatcherUpdateCopyWith<$Res>  {
$BridgeWatcherUpdateCopyWith(BridgeWatcherUpdate _, $Res Function(BridgeWatcherUpdate) __);
}


/// Adds pattern-matching-related methods to [BridgeWatcherUpdate].
extension BridgeWatcherUpdatePatterns on BridgeWatcherUpdate {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeWatcherUpdate_Event value)?  event,TResult Function( BridgeWatcherUpdate_Down value)?  down,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeWatcherUpdate_Event() when event != null:
return event(_that);case BridgeWatcherUpdate_Down() when down != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeWatcherUpdate_Event value)  event,required TResult Function( BridgeWatcherUpdate_Down value)  down,}){
final _that = this;
switch (_that) {
case BridgeWatcherUpdate_Event():
return event(_that);case BridgeWatcherUpdate_Down():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeWatcherUpdate_Event value)?  event,TResult? Function( BridgeWatcherUpdate_Down value)?  down,}){
final _that = this;
switch (_that) {
case BridgeWatcherUpdate_Event() when event != null:
return event(_that);case BridgeWatcherUpdate_Down() when down != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( BridgeRcEvent event,  List<BridgeOverlayEntry> overlay,  bool resync)?  event,TResult Function( String reason)?  down,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeWatcherUpdate_Event() when event != null:
return event(_that.event,_that.overlay,_that.resync);case BridgeWatcherUpdate_Down() when down != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( BridgeRcEvent event,  List<BridgeOverlayEntry> overlay,  bool resync)  event,required TResult Function( String reason)  down,}) {final _that = this;
switch (_that) {
case BridgeWatcherUpdate_Event():
return event(_that.event,_that.overlay,_that.resync);case BridgeWatcherUpdate_Down():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( BridgeRcEvent event,  List<BridgeOverlayEntry> overlay,  bool resync)?  event,TResult? Function( String reason)?  down,}) {final _that = this;
switch (_that) {
case BridgeWatcherUpdate_Event() when event != null:
return event(_that.event,_that.overlay,_that.resync);case BridgeWatcherUpdate_Down() when down != null:
return down(_that.reason);case _:
  return null;

}
}

}

/// @nodoc


class BridgeWatcherUpdate_Event extends BridgeWatcherUpdate {
  const BridgeWatcherUpdate_Event({required this.event, required final  List<BridgeOverlayEntry> overlay, required this.resync}): _overlay = overlay,super._();
  

 final  BridgeRcEvent event;
 final  List<BridgeOverlayEntry> _overlay;
 List<BridgeOverlayEntry> get overlay {
  if (_overlay is EqualUnmodifiableListView) return _overlay;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_overlay);
}

 final  bool resync;

/// Create a copy of BridgeWatcherUpdate
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeWatcherUpdate_EventCopyWith<BridgeWatcherUpdate_Event> get copyWith => _$BridgeWatcherUpdate_EventCopyWithImpl<BridgeWatcherUpdate_Event>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeWatcherUpdate_Event&&(identical(other.event, event) || other.event == event)&&const DeepCollectionEquality().equals(other._overlay, _overlay)&&(identical(other.resync, resync) || other.resync == resync));
}


@override
int get hashCode => Object.hash(runtimeType,event,const DeepCollectionEquality().hash(_overlay),resync);

@override
String toString() {
  return 'BridgeWatcherUpdate.event(event: $event, overlay: $overlay, resync: $resync)';
}


}

/// @nodoc
abstract mixin class $BridgeWatcherUpdate_EventCopyWith<$Res> implements $BridgeWatcherUpdateCopyWith<$Res> {
  factory $BridgeWatcherUpdate_EventCopyWith(BridgeWatcherUpdate_Event value, $Res Function(BridgeWatcherUpdate_Event) _then) = _$BridgeWatcherUpdate_EventCopyWithImpl;
@useResult
$Res call({
 BridgeRcEvent event, List<BridgeOverlayEntry> overlay, bool resync
});


$BridgeRcEventCopyWith<$Res> get event;

}
/// @nodoc
class _$BridgeWatcherUpdate_EventCopyWithImpl<$Res>
    implements $BridgeWatcherUpdate_EventCopyWith<$Res> {
  _$BridgeWatcherUpdate_EventCopyWithImpl(this._self, this._then);

  final BridgeWatcherUpdate_Event _self;
  final $Res Function(BridgeWatcherUpdate_Event) _then;

/// Create a copy of BridgeWatcherUpdate
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? event = null,Object? overlay = null,Object? resync = null,}) {
  return _then(BridgeWatcherUpdate_Event(
event: null == event ? _self.event : event // ignore: cast_nullable_to_non_nullable
as BridgeRcEvent,overlay: null == overlay ? _self._overlay : overlay // ignore: cast_nullable_to_non_nullable
as List<BridgeOverlayEntry>,resync: null == resync ? _self.resync : resync // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

/// Create a copy of BridgeWatcherUpdate
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


class BridgeWatcherUpdate_Down extends BridgeWatcherUpdate {
  const BridgeWatcherUpdate_Down({required this.reason}): super._();
  

 final  String reason;

/// Create a copy of BridgeWatcherUpdate
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeWatcherUpdate_DownCopyWith<BridgeWatcherUpdate_Down> get copyWith => _$BridgeWatcherUpdate_DownCopyWithImpl<BridgeWatcherUpdate_Down>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeWatcherUpdate_Down&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode => Object.hash(runtimeType,reason);

@override
String toString() {
  return 'BridgeWatcherUpdate.down(reason: $reason)';
}


}

/// @nodoc
abstract mixin class $BridgeWatcherUpdate_DownCopyWith<$Res> implements $BridgeWatcherUpdateCopyWith<$Res> {
  factory $BridgeWatcherUpdate_DownCopyWith(BridgeWatcherUpdate_Down value, $Res Function(BridgeWatcherUpdate_Down) _then) = _$BridgeWatcherUpdate_DownCopyWithImpl;
@useResult
$Res call({
 String reason
});




}
/// @nodoc
class _$BridgeWatcherUpdate_DownCopyWithImpl<$Res>
    implements $BridgeWatcherUpdate_DownCopyWith<$Res> {
  _$BridgeWatcherUpdate_DownCopyWithImpl(this._self, this._then);

  final BridgeWatcherUpdate_Down _self;
  final $Res Function(BridgeWatcherUpdate_Down) _then;

/// Create a copy of BridgeWatcherUpdate
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? reason = null,}) {
  return _then(BridgeWatcherUpdate_Down(
reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on

// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'dto_rc.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$BridgeRcEvent {

 String get shed;
/// Create a copy of BridgeRcEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeRcEventCopyWith<BridgeRcEvent> get copyWith => _$BridgeRcEventCopyWithImpl<BridgeRcEvent>(this as BridgeRcEvent, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeRcEvent&&(identical(other.shed, shed) || other.shed == shed));
}


@override
int get hashCode => Object.hash(runtimeType,shed);

@override
String toString() {
  return 'BridgeRcEvent(shed: $shed)';
}


}

/// @nodoc
abstract mixin class $BridgeRcEventCopyWith<$Res>  {
  factory $BridgeRcEventCopyWith(BridgeRcEvent value, $Res Function(BridgeRcEvent) _then) = _$BridgeRcEventCopyWithImpl;
@useResult
$Res call({
 String shed
});




}
/// @nodoc
class _$BridgeRcEventCopyWithImpl<$Res>
    implements $BridgeRcEventCopyWith<$Res> {
  _$BridgeRcEventCopyWithImpl(this._self, this._then);

  final BridgeRcEvent _self;
  final $Res Function(BridgeRcEvent) _then;

/// Create a copy of BridgeRcEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? shed = null,}) {
  return _then(_self.copyWith(
shed: null == shed ? _self.shed : shed // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [BridgeRcEvent].
extension BridgeRcEventPatterns on BridgeRcEvent {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeRcEvent_ActivityChanged value)?  activityChanged,TResult Function( BridgeRcEvent_SessionUpdated value)?  sessionUpdated,TResult Function( BridgeRcEvent_MessageAppended value)?  messageAppended,TResult Function( BridgeRcEvent_HubUnavailable value)?  hubUnavailable,TResult Function( BridgeRcEvent_ShedStopped value)?  shedStopped,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeRcEvent_ActivityChanged() when activityChanged != null:
return activityChanged(_that);case BridgeRcEvent_SessionUpdated() when sessionUpdated != null:
return sessionUpdated(_that);case BridgeRcEvent_MessageAppended() when messageAppended != null:
return messageAppended(_that);case BridgeRcEvent_HubUnavailable() when hubUnavailable != null:
return hubUnavailable(_that);case BridgeRcEvent_ShedStopped() when shedStopped != null:
return shedStopped(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeRcEvent_ActivityChanged value)  activityChanged,required TResult Function( BridgeRcEvent_SessionUpdated value)  sessionUpdated,required TResult Function( BridgeRcEvent_MessageAppended value)  messageAppended,required TResult Function( BridgeRcEvent_HubUnavailable value)  hubUnavailable,required TResult Function( BridgeRcEvent_ShedStopped value)  shedStopped,}){
final _that = this;
switch (_that) {
case BridgeRcEvent_ActivityChanged():
return activityChanged(_that);case BridgeRcEvent_SessionUpdated():
return sessionUpdated(_that);case BridgeRcEvent_MessageAppended():
return messageAppended(_that);case BridgeRcEvent_HubUnavailable():
return hubUnavailable(_that);case BridgeRcEvent_ShedStopped():
return shedStopped(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeRcEvent_ActivityChanged value)?  activityChanged,TResult? Function( BridgeRcEvent_SessionUpdated value)?  sessionUpdated,TResult? Function( BridgeRcEvent_MessageAppended value)?  messageAppended,TResult? Function( BridgeRcEvent_HubUnavailable value)?  hubUnavailable,TResult? Function( BridgeRcEvent_ShedStopped value)?  shedStopped,}){
final _that = this;
switch (_that) {
case BridgeRcEvent_ActivityChanged() when activityChanged != null:
return activityChanged(_that);case BridgeRcEvent_SessionUpdated() when sessionUpdated != null:
return sessionUpdated(_that);case BridgeRcEvent_MessageAppended() when messageAppended != null:
return messageAppended(_that);case BridgeRcEvent_HubUnavailable() when hubUnavailable != null:
return hubUnavailable(_that);case BridgeRcEvent_ShedStopped() when shedStopped != null:
return shedStopped(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String shed,  String slug,  BridgeRcActivity? activity,  String? activityAt,  BridgeRcState? state,  String? lastMessage)?  activityChanged,TResult Function( String shed,  String slug,  BridgeRcActivity? activity,  BridgeRcState? state,  String? lastMessage,  bool removed)?  sessionUpdated,TResult Function( String shed,  String slug,  BigInt seq)?  messageAppended,TResult Function( String shed)?  hubUnavailable,TResult Function( String shed)?  shedStopped,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeRcEvent_ActivityChanged() when activityChanged != null:
return activityChanged(_that.shed,_that.slug,_that.activity,_that.activityAt,_that.state,_that.lastMessage);case BridgeRcEvent_SessionUpdated() when sessionUpdated != null:
return sessionUpdated(_that.shed,_that.slug,_that.activity,_that.state,_that.lastMessage,_that.removed);case BridgeRcEvent_MessageAppended() when messageAppended != null:
return messageAppended(_that.shed,_that.slug,_that.seq);case BridgeRcEvent_HubUnavailable() when hubUnavailable != null:
return hubUnavailable(_that.shed);case BridgeRcEvent_ShedStopped() when shedStopped != null:
return shedStopped(_that.shed);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String shed,  String slug,  BridgeRcActivity? activity,  String? activityAt,  BridgeRcState? state,  String? lastMessage)  activityChanged,required TResult Function( String shed,  String slug,  BridgeRcActivity? activity,  BridgeRcState? state,  String? lastMessage,  bool removed)  sessionUpdated,required TResult Function( String shed,  String slug,  BigInt seq)  messageAppended,required TResult Function( String shed)  hubUnavailable,required TResult Function( String shed)  shedStopped,}) {final _that = this;
switch (_that) {
case BridgeRcEvent_ActivityChanged():
return activityChanged(_that.shed,_that.slug,_that.activity,_that.activityAt,_that.state,_that.lastMessage);case BridgeRcEvent_SessionUpdated():
return sessionUpdated(_that.shed,_that.slug,_that.activity,_that.state,_that.lastMessage,_that.removed);case BridgeRcEvent_MessageAppended():
return messageAppended(_that.shed,_that.slug,_that.seq);case BridgeRcEvent_HubUnavailable():
return hubUnavailable(_that.shed);case BridgeRcEvent_ShedStopped():
return shedStopped(_that.shed);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String shed,  String slug,  BridgeRcActivity? activity,  String? activityAt,  BridgeRcState? state,  String? lastMessage)?  activityChanged,TResult? Function( String shed,  String slug,  BridgeRcActivity? activity,  BridgeRcState? state,  String? lastMessage,  bool removed)?  sessionUpdated,TResult? Function( String shed,  String slug,  BigInt seq)?  messageAppended,TResult? Function( String shed)?  hubUnavailable,TResult? Function( String shed)?  shedStopped,}) {final _that = this;
switch (_that) {
case BridgeRcEvent_ActivityChanged() when activityChanged != null:
return activityChanged(_that.shed,_that.slug,_that.activity,_that.activityAt,_that.state,_that.lastMessage);case BridgeRcEvent_SessionUpdated() when sessionUpdated != null:
return sessionUpdated(_that.shed,_that.slug,_that.activity,_that.state,_that.lastMessage,_that.removed);case BridgeRcEvent_MessageAppended() when messageAppended != null:
return messageAppended(_that.shed,_that.slug,_that.seq);case BridgeRcEvent_HubUnavailable() when hubUnavailable != null:
return hubUnavailable(_that.shed);case BridgeRcEvent_ShedStopped() when shedStopped != null:
return shedStopped(_that.shed);case _:
  return null;

}
}

}

/// @nodoc


class BridgeRcEvent_ActivityChanged extends BridgeRcEvent {
  const BridgeRcEvent_ActivityChanged({required this.shed, required this.slug, this.activity, this.activityAt, this.state, this.lastMessage}): super._();
  

@override final  String shed;
 final  String slug;
 final  BridgeRcActivity? activity;
 final  String? activityAt;
 final  BridgeRcState? state;
 final  String? lastMessage;

/// Create a copy of BridgeRcEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeRcEvent_ActivityChangedCopyWith<BridgeRcEvent_ActivityChanged> get copyWith => _$BridgeRcEvent_ActivityChangedCopyWithImpl<BridgeRcEvent_ActivityChanged>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeRcEvent_ActivityChanged&&(identical(other.shed, shed) || other.shed == shed)&&(identical(other.slug, slug) || other.slug == slug)&&(identical(other.activity, activity) || other.activity == activity)&&(identical(other.activityAt, activityAt) || other.activityAt == activityAt)&&(identical(other.state, state) || other.state == state)&&(identical(other.lastMessage, lastMessage) || other.lastMessage == lastMessage));
}


@override
int get hashCode => Object.hash(runtimeType,shed,slug,activity,activityAt,state,lastMessage);

@override
String toString() {
  return 'BridgeRcEvent.activityChanged(shed: $shed, slug: $slug, activity: $activity, activityAt: $activityAt, state: $state, lastMessage: $lastMessage)';
}


}

/// @nodoc
abstract mixin class $BridgeRcEvent_ActivityChangedCopyWith<$Res> implements $BridgeRcEventCopyWith<$Res> {
  factory $BridgeRcEvent_ActivityChangedCopyWith(BridgeRcEvent_ActivityChanged value, $Res Function(BridgeRcEvent_ActivityChanged) _then) = _$BridgeRcEvent_ActivityChangedCopyWithImpl;
@override @useResult
$Res call({
 String shed, String slug, BridgeRcActivity? activity, String? activityAt, BridgeRcState? state, String? lastMessage
});




}
/// @nodoc
class _$BridgeRcEvent_ActivityChangedCopyWithImpl<$Res>
    implements $BridgeRcEvent_ActivityChangedCopyWith<$Res> {
  _$BridgeRcEvent_ActivityChangedCopyWithImpl(this._self, this._then);

  final BridgeRcEvent_ActivityChanged _self;
  final $Res Function(BridgeRcEvent_ActivityChanged) _then;

/// Create a copy of BridgeRcEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? shed = null,Object? slug = null,Object? activity = freezed,Object? activityAt = freezed,Object? state = freezed,Object? lastMessage = freezed,}) {
  return _then(BridgeRcEvent_ActivityChanged(
shed: null == shed ? _self.shed : shed // ignore: cast_nullable_to_non_nullable
as String,slug: null == slug ? _self.slug : slug // ignore: cast_nullable_to_non_nullable
as String,activity: freezed == activity ? _self.activity : activity // ignore: cast_nullable_to_non_nullable
as BridgeRcActivity?,activityAt: freezed == activityAt ? _self.activityAt : activityAt // ignore: cast_nullable_to_non_nullable
as String?,state: freezed == state ? _self.state : state // ignore: cast_nullable_to_non_nullable
as BridgeRcState?,lastMessage: freezed == lastMessage ? _self.lastMessage : lastMessage // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

/// @nodoc


class BridgeRcEvent_SessionUpdated extends BridgeRcEvent {
  const BridgeRcEvent_SessionUpdated({required this.shed, required this.slug, this.activity, this.state, this.lastMessage, required this.removed}): super._();
  

@override final  String shed;
 final  String slug;
 final  BridgeRcActivity? activity;
 final  BridgeRcState? state;
 final  String? lastMessage;
 final  bool removed;

/// Create a copy of BridgeRcEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeRcEvent_SessionUpdatedCopyWith<BridgeRcEvent_SessionUpdated> get copyWith => _$BridgeRcEvent_SessionUpdatedCopyWithImpl<BridgeRcEvent_SessionUpdated>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeRcEvent_SessionUpdated&&(identical(other.shed, shed) || other.shed == shed)&&(identical(other.slug, slug) || other.slug == slug)&&(identical(other.activity, activity) || other.activity == activity)&&(identical(other.state, state) || other.state == state)&&(identical(other.lastMessage, lastMessage) || other.lastMessage == lastMessage)&&(identical(other.removed, removed) || other.removed == removed));
}


@override
int get hashCode => Object.hash(runtimeType,shed,slug,activity,state,lastMessage,removed);

@override
String toString() {
  return 'BridgeRcEvent.sessionUpdated(shed: $shed, slug: $slug, activity: $activity, state: $state, lastMessage: $lastMessage, removed: $removed)';
}


}

/// @nodoc
abstract mixin class $BridgeRcEvent_SessionUpdatedCopyWith<$Res> implements $BridgeRcEventCopyWith<$Res> {
  factory $BridgeRcEvent_SessionUpdatedCopyWith(BridgeRcEvent_SessionUpdated value, $Res Function(BridgeRcEvent_SessionUpdated) _then) = _$BridgeRcEvent_SessionUpdatedCopyWithImpl;
@override @useResult
$Res call({
 String shed, String slug, BridgeRcActivity? activity, BridgeRcState? state, String? lastMessage, bool removed
});




}
/// @nodoc
class _$BridgeRcEvent_SessionUpdatedCopyWithImpl<$Res>
    implements $BridgeRcEvent_SessionUpdatedCopyWith<$Res> {
  _$BridgeRcEvent_SessionUpdatedCopyWithImpl(this._self, this._then);

  final BridgeRcEvent_SessionUpdated _self;
  final $Res Function(BridgeRcEvent_SessionUpdated) _then;

/// Create a copy of BridgeRcEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? shed = null,Object? slug = null,Object? activity = freezed,Object? state = freezed,Object? lastMessage = freezed,Object? removed = null,}) {
  return _then(BridgeRcEvent_SessionUpdated(
shed: null == shed ? _self.shed : shed // ignore: cast_nullable_to_non_nullable
as String,slug: null == slug ? _self.slug : slug // ignore: cast_nullable_to_non_nullable
as String,activity: freezed == activity ? _self.activity : activity // ignore: cast_nullable_to_non_nullable
as BridgeRcActivity?,state: freezed == state ? _self.state : state // ignore: cast_nullable_to_non_nullable
as BridgeRcState?,lastMessage: freezed == lastMessage ? _self.lastMessage : lastMessage // ignore: cast_nullable_to_non_nullable
as String?,removed: null == removed ? _self.removed : removed // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

/// @nodoc


class BridgeRcEvent_MessageAppended extends BridgeRcEvent {
  const BridgeRcEvent_MessageAppended({required this.shed, required this.slug, required this.seq}): super._();
  

@override final  String shed;
 final  String slug;
 final  BigInt seq;

/// Create a copy of BridgeRcEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeRcEvent_MessageAppendedCopyWith<BridgeRcEvent_MessageAppended> get copyWith => _$BridgeRcEvent_MessageAppendedCopyWithImpl<BridgeRcEvent_MessageAppended>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeRcEvent_MessageAppended&&(identical(other.shed, shed) || other.shed == shed)&&(identical(other.slug, slug) || other.slug == slug)&&(identical(other.seq, seq) || other.seq == seq));
}


@override
int get hashCode => Object.hash(runtimeType,shed,slug,seq);

@override
String toString() {
  return 'BridgeRcEvent.messageAppended(shed: $shed, slug: $slug, seq: $seq)';
}


}

/// @nodoc
abstract mixin class $BridgeRcEvent_MessageAppendedCopyWith<$Res> implements $BridgeRcEventCopyWith<$Res> {
  factory $BridgeRcEvent_MessageAppendedCopyWith(BridgeRcEvent_MessageAppended value, $Res Function(BridgeRcEvent_MessageAppended) _then) = _$BridgeRcEvent_MessageAppendedCopyWithImpl;
@override @useResult
$Res call({
 String shed, String slug, BigInt seq
});




}
/// @nodoc
class _$BridgeRcEvent_MessageAppendedCopyWithImpl<$Res>
    implements $BridgeRcEvent_MessageAppendedCopyWith<$Res> {
  _$BridgeRcEvent_MessageAppendedCopyWithImpl(this._self, this._then);

  final BridgeRcEvent_MessageAppended _self;
  final $Res Function(BridgeRcEvent_MessageAppended) _then;

/// Create a copy of BridgeRcEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? shed = null,Object? slug = null,Object? seq = null,}) {
  return _then(BridgeRcEvent_MessageAppended(
shed: null == shed ? _self.shed : shed // ignore: cast_nullable_to_non_nullable
as String,slug: null == slug ? _self.slug : slug // ignore: cast_nullable_to_non_nullable
as String,seq: null == seq ? _self.seq : seq // ignore: cast_nullable_to_non_nullable
as BigInt,
  ));
}


}

/// @nodoc


class BridgeRcEvent_HubUnavailable extends BridgeRcEvent {
  const BridgeRcEvent_HubUnavailable({required this.shed}): super._();
  

@override final  String shed;

/// Create a copy of BridgeRcEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeRcEvent_HubUnavailableCopyWith<BridgeRcEvent_HubUnavailable> get copyWith => _$BridgeRcEvent_HubUnavailableCopyWithImpl<BridgeRcEvent_HubUnavailable>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeRcEvent_HubUnavailable&&(identical(other.shed, shed) || other.shed == shed));
}


@override
int get hashCode => Object.hash(runtimeType,shed);

@override
String toString() {
  return 'BridgeRcEvent.hubUnavailable(shed: $shed)';
}


}

/// @nodoc
abstract mixin class $BridgeRcEvent_HubUnavailableCopyWith<$Res> implements $BridgeRcEventCopyWith<$Res> {
  factory $BridgeRcEvent_HubUnavailableCopyWith(BridgeRcEvent_HubUnavailable value, $Res Function(BridgeRcEvent_HubUnavailable) _then) = _$BridgeRcEvent_HubUnavailableCopyWithImpl;
@override @useResult
$Res call({
 String shed
});




}
/// @nodoc
class _$BridgeRcEvent_HubUnavailableCopyWithImpl<$Res>
    implements $BridgeRcEvent_HubUnavailableCopyWith<$Res> {
  _$BridgeRcEvent_HubUnavailableCopyWithImpl(this._self, this._then);

  final BridgeRcEvent_HubUnavailable _self;
  final $Res Function(BridgeRcEvent_HubUnavailable) _then;

/// Create a copy of BridgeRcEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? shed = null,}) {
  return _then(BridgeRcEvent_HubUnavailable(
shed: null == shed ? _self.shed : shed // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class BridgeRcEvent_ShedStopped extends BridgeRcEvent {
  const BridgeRcEvent_ShedStopped({required this.shed}): super._();
  

@override final  String shed;

/// Create a copy of BridgeRcEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeRcEvent_ShedStoppedCopyWith<BridgeRcEvent_ShedStopped> get copyWith => _$BridgeRcEvent_ShedStoppedCopyWithImpl<BridgeRcEvent_ShedStopped>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeRcEvent_ShedStopped&&(identical(other.shed, shed) || other.shed == shed));
}


@override
int get hashCode => Object.hash(runtimeType,shed);

@override
String toString() {
  return 'BridgeRcEvent.shedStopped(shed: $shed)';
}


}

/// @nodoc
abstract mixin class $BridgeRcEvent_ShedStoppedCopyWith<$Res> implements $BridgeRcEventCopyWith<$Res> {
  factory $BridgeRcEvent_ShedStoppedCopyWith(BridgeRcEvent_ShedStopped value, $Res Function(BridgeRcEvent_ShedStopped) _then) = _$BridgeRcEvent_ShedStoppedCopyWithImpl;
@override @useResult
$Res call({
 String shed
});




}
/// @nodoc
class _$BridgeRcEvent_ShedStoppedCopyWithImpl<$Res>
    implements $BridgeRcEvent_ShedStoppedCopyWith<$Res> {
  _$BridgeRcEvent_ShedStoppedCopyWithImpl(this._self, this._then);

  final BridgeRcEvent_ShedStopped _self;
  final $Res Function(BridgeRcEvent_ShedStopped) _then;

/// Create a copy of BridgeRcEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? shed = null,}) {
  return _then(BridgeRcEvent_ShedStopped(
shed: null == shed ? _self.shed : shed // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$BridgeRcKind {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeRcKind);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'BridgeRcKind()';
}


}

/// @nodoc
class $BridgeRcKindCopyWith<$Res>  {
$BridgeRcKindCopyWith(BridgeRcKind _, $Res Function(BridgeRcKind) __);
}


/// Adds pattern-matching-related methods to [BridgeRcKind].
extension BridgeRcKindPatterns on BridgeRcKind {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeRcKind_ClaudeRc value)?  claudeRc,TResult Function( BridgeRcKind_ClaudeBroker value)?  claudeBroker,TResult Function( BridgeRcKind_Codex value)?  codex,TResult Function( BridgeRcKind_Opencode value)?  opencode,TResult Function( BridgeRcKind_Cursor value)?  cursor,TResult Function( BridgeRcKind_Shell value)?  shell,TResult Function( BridgeRcKind_Other value)?  other,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeRcKind_ClaudeRc() when claudeRc != null:
return claudeRc(_that);case BridgeRcKind_ClaudeBroker() when claudeBroker != null:
return claudeBroker(_that);case BridgeRcKind_Codex() when codex != null:
return codex(_that);case BridgeRcKind_Opencode() when opencode != null:
return opencode(_that);case BridgeRcKind_Cursor() when cursor != null:
return cursor(_that);case BridgeRcKind_Shell() when shell != null:
return shell(_that);case BridgeRcKind_Other() when other != null:
return other(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeRcKind_ClaudeRc value)  claudeRc,required TResult Function( BridgeRcKind_ClaudeBroker value)  claudeBroker,required TResult Function( BridgeRcKind_Codex value)  codex,required TResult Function( BridgeRcKind_Opencode value)  opencode,required TResult Function( BridgeRcKind_Cursor value)  cursor,required TResult Function( BridgeRcKind_Shell value)  shell,required TResult Function( BridgeRcKind_Other value)  other,}){
final _that = this;
switch (_that) {
case BridgeRcKind_ClaudeRc():
return claudeRc(_that);case BridgeRcKind_ClaudeBroker():
return claudeBroker(_that);case BridgeRcKind_Codex():
return codex(_that);case BridgeRcKind_Opencode():
return opencode(_that);case BridgeRcKind_Cursor():
return cursor(_that);case BridgeRcKind_Shell():
return shell(_that);case BridgeRcKind_Other():
return other(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeRcKind_ClaudeRc value)?  claudeRc,TResult? Function( BridgeRcKind_ClaudeBroker value)?  claudeBroker,TResult? Function( BridgeRcKind_Codex value)?  codex,TResult? Function( BridgeRcKind_Opencode value)?  opencode,TResult? Function( BridgeRcKind_Cursor value)?  cursor,TResult? Function( BridgeRcKind_Shell value)?  shell,TResult? Function( BridgeRcKind_Other value)?  other,}){
final _that = this;
switch (_that) {
case BridgeRcKind_ClaudeRc() when claudeRc != null:
return claudeRc(_that);case BridgeRcKind_ClaudeBroker() when claudeBroker != null:
return claudeBroker(_that);case BridgeRcKind_Codex() when codex != null:
return codex(_that);case BridgeRcKind_Opencode() when opencode != null:
return opencode(_that);case BridgeRcKind_Cursor() when cursor != null:
return cursor(_that);case BridgeRcKind_Shell() when shell != null:
return shell(_that);case BridgeRcKind_Other() when other != null:
return other(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  claudeRc,TResult Function()?  claudeBroker,TResult Function()?  codex,TResult Function()?  opencode,TResult Function()?  cursor,TResult Function()?  shell,TResult Function( String raw)?  other,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeRcKind_ClaudeRc() when claudeRc != null:
return claudeRc();case BridgeRcKind_ClaudeBroker() when claudeBroker != null:
return claudeBroker();case BridgeRcKind_Codex() when codex != null:
return codex();case BridgeRcKind_Opencode() when opencode != null:
return opencode();case BridgeRcKind_Cursor() when cursor != null:
return cursor();case BridgeRcKind_Shell() when shell != null:
return shell();case BridgeRcKind_Other() when other != null:
return other(_that.raw);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  claudeRc,required TResult Function()  claudeBroker,required TResult Function()  codex,required TResult Function()  opencode,required TResult Function()  cursor,required TResult Function()  shell,required TResult Function( String raw)  other,}) {final _that = this;
switch (_that) {
case BridgeRcKind_ClaudeRc():
return claudeRc();case BridgeRcKind_ClaudeBroker():
return claudeBroker();case BridgeRcKind_Codex():
return codex();case BridgeRcKind_Opencode():
return opencode();case BridgeRcKind_Cursor():
return cursor();case BridgeRcKind_Shell():
return shell();case BridgeRcKind_Other():
return other(_that.raw);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  claudeRc,TResult? Function()?  claudeBroker,TResult? Function()?  codex,TResult? Function()?  opencode,TResult? Function()?  cursor,TResult? Function()?  shell,TResult? Function( String raw)?  other,}) {final _that = this;
switch (_that) {
case BridgeRcKind_ClaudeRc() when claudeRc != null:
return claudeRc();case BridgeRcKind_ClaudeBroker() when claudeBroker != null:
return claudeBroker();case BridgeRcKind_Codex() when codex != null:
return codex();case BridgeRcKind_Opencode() when opencode != null:
return opencode();case BridgeRcKind_Cursor() when cursor != null:
return cursor();case BridgeRcKind_Shell() when shell != null:
return shell();case BridgeRcKind_Other() when other != null:
return other(_that.raw);case _:
  return null;

}
}

}

/// @nodoc


class BridgeRcKind_ClaudeRc extends BridgeRcKind {
  const BridgeRcKind_ClaudeRc(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeRcKind_ClaudeRc);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'BridgeRcKind.claudeRc()';
}


}




/// @nodoc


class BridgeRcKind_ClaudeBroker extends BridgeRcKind {
  const BridgeRcKind_ClaudeBroker(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeRcKind_ClaudeBroker);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'BridgeRcKind.claudeBroker()';
}


}




/// @nodoc


class BridgeRcKind_Codex extends BridgeRcKind {
  const BridgeRcKind_Codex(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeRcKind_Codex);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'BridgeRcKind.codex()';
}


}




/// @nodoc


class BridgeRcKind_Opencode extends BridgeRcKind {
  const BridgeRcKind_Opencode(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeRcKind_Opencode);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'BridgeRcKind.opencode()';
}


}




/// @nodoc


class BridgeRcKind_Cursor extends BridgeRcKind {
  const BridgeRcKind_Cursor(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeRcKind_Cursor);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'BridgeRcKind.cursor()';
}


}




/// @nodoc


class BridgeRcKind_Shell extends BridgeRcKind {
  const BridgeRcKind_Shell(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeRcKind_Shell);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'BridgeRcKind.shell()';
}


}




/// @nodoc


class BridgeRcKind_Other extends BridgeRcKind {
  const BridgeRcKind_Other({required this.raw}): super._();
  

 final  String raw;

/// Create a copy of BridgeRcKind
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeRcKind_OtherCopyWith<BridgeRcKind_Other> get copyWith => _$BridgeRcKind_OtherCopyWithImpl<BridgeRcKind_Other>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeRcKind_Other&&(identical(other.raw, raw) || other.raw == raw));
}


@override
int get hashCode => Object.hash(runtimeType,raw);

@override
String toString() {
  return 'BridgeRcKind.other(raw: $raw)';
}


}

/// @nodoc
abstract mixin class $BridgeRcKind_OtherCopyWith<$Res> implements $BridgeRcKindCopyWith<$Res> {
  factory $BridgeRcKind_OtherCopyWith(BridgeRcKind_Other value, $Res Function(BridgeRcKind_Other) _then) = _$BridgeRcKind_OtherCopyWithImpl;
@useResult
$Res call({
 String raw
});




}
/// @nodoc
class _$BridgeRcKind_OtherCopyWithImpl<$Res>
    implements $BridgeRcKind_OtherCopyWith<$Res> {
  _$BridgeRcKind_OtherCopyWithImpl(this._self, this._then);

  final BridgeRcKind_Other _self;
  final $Res Function(BridgeRcKind_Other) _then;

/// Create a copy of BridgeRcKind
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? raw = null,}) {
  return _then(BridgeRcKind_Other(
raw: null == raw ? _self.raw : raw // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on

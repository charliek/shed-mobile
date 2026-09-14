// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'roost_bootstrap.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$BridgeBootstrapPlan {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeBootstrapPlan);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'BridgeBootstrapPlan()';
}


}

/// @nodoc
class $BridgeBootstrapPlanCopyWith<$Res>  {
$BridgeBootstrapPlanCopyWith(BridgeBootstrapPlan _, $Res Function(BridgeBootstrapPlan) __);
}


/// Adds pattern-matching-related methods to [BridgeBootstrapPlan].
extension BridgeBootstrapPlanPatterns on BridgeBootstrapPlan {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeBootstrapPlan_Install value)?  install,TResult Function( BridgeBootstrapPlan_Update value)?  update,TResult Function( BridgeBootstrapPlan_Start value)?  start,TResult Function( BridgeBootstrapPlan_UpToDate value)?  upToDate,TResult Function( BridgeBootstrapPlan_Report value)?  report,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeBootstrapPlan_Install() when install != null:
return install(_that);case BridgeBootstrapPlan_Update() when update != null:
return update(_that);case BridgeBootstrapPlan_Start() when start != null:
return start(_that);case BridgeBootstrapPlan_UpToDate() when upToDate != null:
return upToDate(_that);case BridgeBootstrapPlan_Report() when report != null:
return report(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeBootstrapPlan_Install value)  install,required TResult Function( BridgeBootstrapPlan_Update value)  update,required TResult Function( BridgeBootstrapPlan_Start value)  start,required TResult Function( BridgeBootstrapPlan_UpToDate value)  upToDate,required TResult Function( BridgeBootstrapPlan_Report value)  report,}){
final _that = this;
switch (_that) {
case BridgeBootstrapPlan_Install():
return install(_that);case BridgeBootstrapPlan_Update():
return update(_that);case BridgeBootstrapPlan_Start():
return start(_that);case BridgeBootstrapPlan_UpToDate():
return upToDate(_that);case BridgeBootstrapPlan_Report():
return report(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeBootstrapPlan_Install value)?  install,TResult? Function( BridgeBootstrapPlan_Update value)?  update,TResult? Function( BridgeBootstrapPlan_Start value)?  start,TResult? Function( BridgeBootstrapPlan_UpToDate value)?  upToDate,TResult? Function( BridgeBootstrapPlan_Report value)?  report,}){
final _that = this;
switch (_that) {
case BridgeBootstrapPlan_Install() when install != null:
return install(_that);case BridgeBootstrapPlan_Update() when update != null:
return update(_that);case BridgeBootstrapPlan_Start() when start != null:
return start(_that);case BridgeBootstrapPlan_UpToDate() when upToDate != null:
return upToDate(_that);case BridgeBootstrapPlan_Report() when report != null:
return report(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String? dest)?  install,TResult Function( String path,  BridgeBootstrapIdentity? incumbent,  bool replacesNewer,  String? dest)?  update,TResult Function( String path)?  start,TResult Function( BridgeBootstrapSessionIdentity identity)?  upToDate,TResult Function( int protocol,  String message)?  report,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeBootstrapPlan_Install() when install != null:
return install(_that.dest);case BridgeBootstrapPlan_Update() when update != null:
return update(_that.path,_that.incumbent,_that.replacesNewer,_that.dest);case BridgeBootstrapPlan_Start() when start != null:
return start(_that.path);case BridgeBootstrapPlan_UpToDate() when upToDate != null:
return upToDate(_that.identity);case BridgeBootstrapPlan_Report() when report != null:
return report(_that.protocol,_that.message);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String? dest)  install,required TResult Function( String path,  BridgeBootstrapIdentity? incumbent,  bool replacesNewer,  String? dest)  update,required TResult Function( String path)  start,required TResult Function( BridgeBootstrapSessionIdentity identity)  upToDate,required TResult Function( int protocol,  String message)  report,}) {final _that = this;
switch (_that) {
case BridgeBootstrapPlan_Install():
return install(_that.dest);case BridgeBootstrapPlan_Update():
return update(_that.path,_that.incumbent,_that.replacesNewer,_that.dest);case BridgeBootstrapPlan_Start():
return start(_that.path);case BridgeBootstrapPlan_UpToDate():
return upToDate(_that.identity);case BridgeBootstrapPlan_Report():
return report(_that.protocol,_that.message);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String? dest)?  install,TResult? Function( String path,  BridgeBootstrapIdentity? incumbent,  bool replacesNewer,  String? dest)?  update,TResult? Function( String path)?  start,TResult? Function( BridgeBootstrapSessionIdentity identity)?  upToDate,TResult? Function( int protocol,  String message)?  report,}) {final _that = this;
switch (_that) {
case BridgeBootstrapPlan_Install() when install != null:
return install(_that.dest);case BridgeBootstrapPlan_Update() when update != null:
return update(_that.path,_that.incumbent,_that.replacesNewer,_that.dest);case BridgeBootstrapPlan_Start() when start != null:
return start(_that.path);case BridgeBootstrapPlan_UpToDate() when upToDate != null:
return upToDate(_that.identity);case BridgeBootstrapPlan_Report() when report != null:
return report(_that.protocol,_that.message);case _:
  return null;

}
}

}

/// @nodoc


class BridgeBootstrapPlan_Install extends BridgeBootstrapPlan {
  const BridgeBootstrapPlan_Install({this.dest}): super._();
  

/// Where it will land, when the remote reported a `$HOME`.
 final  String? dest;

/// Create a copy of BridgeBootstrapPlan
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeBootstrapPlan_InstallCopyWith<BridgeBootstrapPlan_Install> get copyWith => _$BridgeBootstrapPlan_InstallCopyWithImpl<BridgeBootstrapPlan_Install>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeBootstrapPlan_Install&&(identical(other.dest, dest) || other.dest == dest));
}


@override
int get hashCode => Object.hash(runtimeType,dest);

@override
String toString() {
  return 'BridgeBootstrapPlan.install(dest: $dest)';
}


}

/// @nodoc
abstract mixin class $BridgeBootstrapPlan_InstallCopyWith<$Res> implements $BridgeBootstrapPlanCopyWith<$Res> {
  factory $BridgeBootstrapPlan_InstallCopyWith(BridgeBootstrapPlan_Install value, $Res Function(BridgeBootstrapPlan_Install) _then) = _$BridgeBootstrapPlan_InstallCopyWithImpl;
@useResult
$Res call({
 String? dest
});




}
/// @nodoc
class _$BridgeBootstrapPlan_InstallCopyWithImpl<$Res>
    implements $BridgeBootstrapPlan_InstallCopyWith<$Res> {
  _$BridgeBootstrapPlan_InstallCopyWithImpl(this._self, this._then);

  final BridgeBootstrapPlan_Install _self;
  final $Res Function(BridgeBootstrapPlan_Install) _then;

/// Create a copy of BridgeBootstrapPlan
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? dest = freezed,}) {
  return _then(BridgeBootstrapPlan_Install(
dest: freezed == dest ? _self.dest : dest // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

/// @nodoc


class BridgeBootstrapPlan_Update extends BridgeBootstrapPlan {
  const BridgeBootstrapPlan_Update({required this.path, this.incumbent, required this.replacesNewer, this.dest}): super._();
  

/// The rung that would be shadowed — informational; an install always
/// lands on rung 1.
 final  String path;
 final  BridgeBootstrapIdentity? incumbent;
/// The incumbent speaks a **newer** protocol than this build, so this is
/// a downgrade wearing an update's clothes. The sheet says so rather
/// than letting the user find out afterwards.
 final  bool replacesNewer;
 final  String? dest;

/// Create a copy of BridgeBootstrapPlan
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeBootstrapPlan_UpdateCopyWith<BridgeBootstrapPlan_Update> get copyWith => _$BridgeBootstrapPlan_UpdateCopyWithImpl<BridgeBootstrapPlan_Update>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeBootstrapPlan_Update&&(identical(other.path, path) || other.path == path)&&(identical(other.incumbent, incumbent) || other.incumbent == incumbent)&&(identical(other.replacesNewer, replacesNewer) || other.replacesNewer == replacesNewer)&&(identical(other.dest, dest) || other.dest == dest));
}


@override
int get hashCode => Object.hash(runtimeType,path,incumbent,replacesNewer,dest);

@override
String toString() {
  return 'BridgeBootstrapPlan.update(path: $path, incumbent: $incumbent, replacesNewer: $replacesNewer, dest: $dest)';
}


}

/// @nodoc
abstract mixin class $BridgeBootstrapPlan_UpdateCopyWith<$Res> implements $BridgeBootstrapPlanCopyWith<$Res> {
  factory $BridgeBootstrapPlan_UpdateCopyWith(BridgeBootstrapPlan_Update value, $Res Function(BridgeBootstrapPlan_Update) _then) = _$BridgeBootstrapPlan_UpdateCopyWithImpl;
@useResult
$Res call({
 String path, BridgeBootstrapIdentity? incumbent, bool replacesNewer, String? dest
});




}
/// @nodoc
class _$BridgeBootstrapPlan_UpdateCopyWithImpl<$Res>
    implements $BridgeBootstrapPlan_UpdateCopyWith<$Res> {
  _$BridgeBootstrapPlan_UpdateCopyWithImpl(this._self, this._then);

  final BridgeBootstrapPlan_Update _self;
  final $Res Function(BridgeBootstrapPlan_Update) _then;

/// Create a copy of BridgeBootstrapPlan
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? path = null,Object? incumbent = freezed,Object? replacesNewer = null,Object? dest = freezed,}) {
  return _then(BridgeBootstrapPlan_Update(
path: null == path ? _self.path : path // ignore: cast_nullable_to_non_nullable
as String,incumbent: freezed == incumbent ? _self.incumbent : incumbent // ignore: cast_nullable_to_non_nullable
as BridgeBootstrapIdentity?,replacesNewer: null == replacesNewer ? _self.replacesNewer : replacesNewer // ignore: cast_nullable_to_non_nullable
as bool,dest: freezed == dest ? _self.dest : dest // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

/// @nodoc


class BridgeBootstrapPlan_Start extends BridgeBootstrapPlan {
  const BridgeBootstrapPlan_Start({required this.path}): super._();
  

 final  String path;

/// Create a copy of BridgeBootstrapPlan
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeBootstrapPlan_StartCopyWith<BridgeBootstrapPlan_Start> get copyWith => _$BridgeBootstrapPlan_StartCopyWithImpl<BridgeBootstrapPlan_Start>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeBootstrapPlan_Start&&(identical(other.path, path) || other.path == path));
}


@override
int get hashCode => Object.hash(runtimeType,path);

@override
String toString() {
  return 'BridgeBootstrapPlan.start(path: $path)';
}


}

/// @nodoc
abstract mixin class $BridgeBootstrapPlan_StartCopyWith<$Res> implements $BridgeBootstrapPlanCopyWith<$Res> {
  factory $BridgeBootstrapPlan_StartCopyWith(BridgeBootstrapPlan_Start value, $Res Function(BridgeBootstrapPlan_Start) _then) = _$BridgeBootstrapPlan_StartCopyWithImpl;
@useResult
$Res call({
 String path
});




}
/// @nodoc
class _$BridgeBootstrapPlan_StartCopyWithImpl<$Res>
    implements $BridgeBootstrapPlan_StartCopyWith<$Res> {
  _$BridgeBootstrapPlan_StartCopyWithImpl(this._self, this._then);

  final BridgeBootstrapPlan_Start _self;
  final $Res Function(BridgeBootstrapPlan_Start) _then;

/// Create a copy of BridgeBootstrapPlan
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? path = null,}) {
  return _then(BridgeBootstrapPlan_Start(
path: null == path ? _self.path : path // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class BridgeBootstrapPlan_UpToDate extends BridgeBootstrapPlan {
  const BridgeBootstrapPlan_UpToDate({required this.identity}): super._();
  

 final  BridgeBootstrapSessionIdentity identity;

/// Create a copy of BridgeBootstrapPlan
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeBootstrapPlan_UpToDateCopyWith<BridgeBootstrapPlan_UpToDate> get copyWith => _$BridgeBootstrapPlan_UpToDateCopyWithImpl<BridgeBootstrapPlan_UpToDate>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeBootstrapPlan_UpToDate&&(identical(other.identity, identity) || other.identity == identity));
}


@override
int get hashCode => Object.hash(runtimeType,identity);

@override
String toString() {
  return 'BridgeBootstrapPlan.upToDate(identity: $identity)';
}


}

/// @nodoc
abstract mixin class $BridgeBootstrapPlan_UpToDateCopyWith<$Res> implements $BridgeBootstrapPlanCopyWith<$Res> {
  factory $BridgeBootstrapPlan_UpToDateCopyWith(BridgeBootstrapPlan_UpToDate value, $Res Function(BridgeBootstrapPlan_UpToDate) _then) = _$BridgeBootstrapPlan_UpToDateCopyWithImpl;
@useResult
$Res call({
 BridgeBootstrapSessionIdentity identity
});




}
/// @nodoc
class _$BridgeBootstrapPlan_UpToDateCopyWithImpl<$Res>
    implements $BridgeBootstrapPlan_UpToDateCopyWith<$Res> {
  _$BridgeBootstrapPlan_UpToDateCopyWithImpl(this._self, this._then);

  final BridgeBootstrapPlan_UpToDate _self;
  final $Res Function(BridgeBootstrapPlan_UpToDate) _then;

/// Create a copy of BridgeBootstrapPlan
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? identity = null,}) {
  return _then(BridgeBootstrapPlan_UpToDate(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as BridgeBootstrapSessionIdentity,
  ));
}


}

/// @nodoc


class BridgeBootstrapPlan_Report extends BridgeBootstrapPlan {
  const BridgeBootstrapPlan_Report({required this.protocol, required this.message}): super._();
  

 final  int protocol;
 final  String message;

/// Create a copy of BridgeBootstrapPlan
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeBootstrapPlan_ReportCopyWith<BridgeBootstrapPlan_Report> get copyWith => _$BridgeBootstrapPlan_ReportCopyWithImpl<BridgeBootstrapPlan_Report>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeBootstrapPlan_Report&&(identical(other.protocol, protocol) || other.protocol == protocol)&&(identical(other.message, message) || other.message == message));
}


@override
int get hashCode => Object.hash(runtimeType,protocol,message);

@override
String toString() {
  return 'BridgeBootstrapPlan.report(protocol: $protocol, message: $message)';
}


}

/// @nodoc
abstract mixin class $BridgeBootstrapPlan_ReportCopyWith<$Res> implements $BridgeBootstrapPlanCopyWith<$Res> {
  factory $BridgeBootstrapPlan_ReportCopyWith(BridgeBootstrapPlan_Report value, $Res Function(BridgeBootstrapPlan_Report) _then) = _$BridgeBootstrapPlan_ReportCopyWithImpl;
@useResult
$Res call({
 int protocol, String message
});




}
/// @nodoc
class _$BridgeBootstrapPlan_ReportCopyWithImpl<$Res>
    implements $BridgeBootstrapPlan_ReportCopyWith<$Res> {
  _$BridgeBootstrapPlan_ReportCopyWithImpl(this._self, this._then);

  final BridgeBootstrapPlan_Report _self;
  final $Res Function(BridgeBootstrapPlan_Report) _then;

/// Create a copy of BridgeBootstrapPlan
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? protocol = null,Object? message = null,}) {
  return _then(BridgeBootstrapPlan_Report(
protocol: null == protocol ? _self.protocol : protocol // ignore: cast_nullable_to_non_nullable
as int,message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$BridgeBootstrapProbeOutcome {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeBootstrapProbeOutcome);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'BridgeBootstrapProbeOutcome()';
}


}

/// @nodoc
class $BridgeBootstrapProbeOutcomeCopyWith<$Res>  {
$BridgeBootstrapProbeOutcomeCopyWith(BridgeBootstrapProbeOutcome _, $Res Function(BridgeBootstrapProbeOutcome) __);
}


/// Adds pattern-matching-related methods to [BridgeBootstrapProbeOutcome].
extension BridgeBootstrapProbeOutcomePatterns on BridgeBootstrapProbeOutcome {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeBootstrapProbeOutcome_Compatible value)?  compatible,TResult Function( BridgeBootstrapProbeOutcome_Mismatch value)?  mismatch,TResult Function( BridgeBootstrapProbeOutcome_Missing value)?  missing,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeBootstrapProbeOutcome_Compatible() when compatible != null:
return compatible(_that);case BridgeBootstrapProbeOutcome_Mismatch() when mismatch != null:
return mismatch(_that);case BridgeBootstrapProbeOutcome_Missing() when missing != null:
return missing(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeBootstrapProbeOutcome_Compatible value)  compatible,required TResult Function( BridgeBootstrapProbeOutcome_Mismatch value)  mismatch,required TResult Function( BridgeBootstrapProbeOutcome_Missing value)  missing,}){
final _that = this;
switch (_that) {
case BridgeBootstrapProbeOutcome_Compatible():
return compatible(_that);case BridgeBootstrapProbeOutcome_Mismatch():
return mismatch(_that);case BridgeBootstrapProbeOutcome_Missing():
return missing(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeBootstrapProbeOutcome_Compatible value)?  compatible,TResult? Function( BridgeBootstrapProbeOutcome_Mismatch value)?  mismatch,TResult? Function( BridgeBootstrapProbeOutcome_Missing value)?  missing,}){
final _that = this;
switch (_that) {
case BridgeBootstrapProbeOutcome_Compatible() when compatible != null:
return compatible(_that);case BridgeBootstrapProbeOutcome_Mismatch() when mismatch != null:
return mismatch(_that);case BridgeBootstrapProbeOutcome_Missing() when missing != null:
return missing(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String path,  BridgeBootstrapIdentity identity)?  compatible,TResult Function( String path,  BridgeBootstrapIdentity? identity)?  mismatch,TResult Function()?  missing,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeBootstrapProbeOutcome_Compatible() when compatible != null:
return compatible(_that.path,_that.identity);case BridgeBootstrapProbeOutcome_Mismatch() when mismatch != null:
return mismatch(_that.path,_that.identity);case BridgeBootstrapProbeOutcome_Missing() when missing != null:
return missing();case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String path,  BridgeBootstrapIdentity identity)  compatible,required TResult Function( String path,  BridgeBootstrapIdentity? identity)  mismatch,required TResult Function()  missing,}) {final _that = this;
switch (_that) {
case BridgeBootstrapProbeOutcome_Compatible():
return compatible(_that.path,_that.identity);case BridgeBootstrapProbeOutcome_Mismatch():
return mismatch(_that.path,_that.identity);case BridgeBootstrapProbeOutcome_Missing():
return missing();}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String path,  BridgeBootstrapIdentity identity)?  compatible,TResult? Function( String path,  BridgeBootstrapIdentity? identity)?  mismatch,TResult? Function()?  missing,}) {final _that = this;
switch (_that) {
case BridgeBootstrapProbeOutcome_Compatible() when compatible != null:
return compatible(_that.path,_that.identity);case BridgeBootstrapProbeOutcome_Mismatch() when mismatch != null:
return mismatch(_that.path,_that.identity);case BridgeBootstrapProbeOutcome_Missing() when missing != null:
return missing();case _:
  return null;

}
}

}

/// @nodoc


class BridgeBootstrapProbeOutcome_Compatible extends BridgeBootstrapProbeOutcome {
  const BridgeBootstrapProbeOutcome_Compatible({required this.path, required this.identity}): super._();
  

 final  String path;
 final  BridgeBootstrapIdentity identity;

/// Create a copy of BridgeBootstrapProbeOutcome
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeBootstrapProbeOutcome_CompatibleCopyWith<BridgeBootstrapProbeOutcome_Compatible> get copyWith => _$BridgeBootstrapProbeOutcome_CompatibleCopyWithImpl<BridgeBootstrapProbeOutcome_Compatible>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeBootstrapProbeOutcome_Compatible&&(identical(other.path, path) || other.path == path)&&(identical(other.identity, identity) || other.identity == identity));
}


@override
int get hashCode => Object.hash(runtimeType,path,identity);

@override
String toString() {
  return 'BridgeBootstrapProbeOutcome.compatible(path: $path, identity: $identity)';
}


}

/// @nodoc
abstract mixin class $BridgeBootstrapProbeOutcome_CompatibleCopyWith<$Res> implements $BridgeBootstrapProbeOutcomeCopyWith<$Res> {
  factory $BridgeBootstrapProbeOutcome_CompatibleCopyWith(BridgeBootstrapProbeOutcome_Compatible value, $Res Function(BridgeBootstrapProbeOutcome_Compatible) _then) = _$BridgeBootstrapProbeOutcome_CompatibleCopyWithImpl;
@useResult
$Res call({
 String path, BridgeBootstrapIdentity identity
});




}
/// @nodoc
class _$BridgeBootstrapProbeOutcome_CompatibleCopyWithImpl<$Res>
    implements $BridgeBootstrapProbeOutcome_CompatibleCopyWith<$Res> {
  _$BridgeBootstrapProbeOutcome_CompatibleCopyWithImpl(this._self, this._then);

  final BridgeBootstrapProbeOutcome_Compatible _self;
  final $Res Function(BridgeBootstrapProbeOutcome_Compatible) _then;

/// Create a copy of BridgeBootstrapProbeOutcome
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? path = null,Object? identity = null,}) {
  return _then(BridgeBootstrapProbeOutcome_Compatible(
path: null == path ? _self.path : path // ignore: cast_nullable_to_non_nullable
as String,identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as BridgeBootstrapIdentity,
  ));
}


}

/// @nodoc


class BridgeBootstrapProbeOutcome_Mismatch extends BridgeBootstrapProbeOutcome {
  const BridgeBootstrapProbeOutcome_Mismatch({required this.path, this.identity}): super._();
  

 final  String path;
 final  BridgeBootstrapIdentity? identity;

/// Create a copy of BridgeBootstrapProbeOutcome
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeBootstrapProbeOutcome_MismatchCopyWith<BridgeBootstrapProbeOutcome_Mismatch> get copyWith => _$BridgeBootstrapProbeOutcome_MismatchCopyWithImpl<BridgeBootstrapProbeOutcome_Mismatch>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeBootstrapProbeOutcome_Mismatch&&(identical(other.path, path) || other.path == path)&&(identical(other.identity, identity) || other.identity == identity));
}


@override
int get hashCode => Object.hash(runtimeType,path,identity);

@override
String toString() {
  return 'BridgeBootstrapProbeOutcome.mismatch(path: $path, identity: $identity)';
}


}

/// @nodoc
abstract mixin class $BridgeBootstrapProbeOutcome_MismatchCopyWith<$Res> implements $BridgeBootstrapProbeOutcomeCopyWith<$Res> {
  factory $BridgeBootstrapProbeOutcome_MismatchCopyWith(BridgeBootstrapProbeOutcome_Mismatch value, $Res Function(BridgeBootstrapProbeOutcome_Mismatch) _then) = _$BridgeBootstrapProbeOutcome_MismatchCopyWithImpl;
@useResult
$Res call({
 String path, BridgeBootstrapIdentity? identity
});




}
/// @nodoc
class _$BridgeBootstrapProbeOutcome_MismatchCopyWithImpl<$Res>
    implements $BridgeBootstrapProbeOutcome_MismatchCopyWith<$Res> {
  _$BridgeBootstrapProbeOutcome_MismatchCopyWithImpl(this._self, this._then);

  final BridgeBootstrapProbeOutcome_Mismatch _self;
  final $Res Function(BridgeBootstrapProbeOutcome_Mismatch) _then;

/// Create a copy of BridgeBootstrapProbeOutcome
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? path = null,Object? identity = freezed,}) {
  return _then(BridgeBootstrapProbeOutcome_Mismatch(
path: null == path ? _self.path : path // ignore: cast_nullable_to_non_nullable
as String,identity: freezed == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as BridgeBootstrapIdentity?,
  ));
}


}

/// @nodoc


class BridgeBootstrapProbeOutcome_Missing extends BridgeBootstrapProbeOutcome {
  const BridgeBootstrapProbeOutcome_Missing(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeBootstrapProbeOutcome_Missing);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'BridgeBootstrapProbeOutcome.missing()';
}


}




/// @nodoc
mixin _$BridgeBootstrapSessionState {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeBootstrapSessionState);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'BridgeBootstrapSessionState()';
}


}

/// @nodoc
class $BridgeBootstrapSessionStateCopyWith<$Res>  {
$BridgeBootstrapSessionStateCopyWith(BridgeBootstrapSessionState _, $Res Function(BridgeBootstrapSessionState) __);
}


/// Adds pattern-matching-related methods to [BridgeBootstrapSessionState].
extension BridgeBootstrapSessionStatePatterns on BridgeBootstrapSessionState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeBootstrapSessionState_Running value)?  running,TResult Function( BridgeBootstrapSessionState_NoSession value)?  noSession,TResult Function( BridgeBootstrapSessionState_NotInstalled value)?  notInstalled,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeBootstrapSessionState_Running() when running != null:
return running(_that);case BridgeBootstrapSessionState_NoSession() when noSession != null:
return noSession(_that);case BridgeBootstrapSessionState_NotInstalled() when notInstalled != null:
return notInstalled(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeBootstrapSessionState_Running value)  running,required TResult Function( BridgeBootstrapSessionState_NoSession value)  noSession,required TResult Function( BridgeBootstrapSessionState_NotInstalled value)  notInstalled,}){
final _that = this;
switch (_that) {
case BridgeBootstrapSessionState_Running():
return running(_that);case BridgeBootstrapSessionState_NoSession():
return noSession(_that);case BridgeBootstrapSessionState_NotInstalled():
return notInstalled(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeBootstrapSessionState_Running value)?  running,TResult? Function( BridgeBootstrapSessionState_NoSession value)?  noSession,TResult? Function( BridgeBootstrapSessionState_NotInstalled value)?  notInstalled,}){
final _that = this;
switch (_that) {
case BridgeBootstrapSessionState_Running() when running != null:
return running(_that);case BridgeBootstrapSessionState_NoSession() when noSession != null:
return noSession(_that);case BridgeBootstrapSessionState_NotInstalled() when notInstalled != null:
return notInstalled(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( BridgeBootstrapSessionIdentity identity)?  running,TResult Function()?  noSession,TResult Function()?  notInstalled,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeBootstrapSessionState_Running() when running != null:
return running(_that.identity);case BridgeBootstrapSessionState_NoSession() when noSession != null:
return noSession();case BridgeBootstrapSessionState_NotInstalled() when notInstalled != null:
return notInstalled();case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( BridgeBootstrapSessionIdentity identity)  running,required TResult Function()  noSession,required TResult Function()  notInstalled,}) {final _that = this;
switch (_that) {
case BridgeBootstrapSessionState_Running():
return running(_that.identity);case BridgeBootstrapSessionState_NoSession():
return noSession();case BridgeBootstrapSessionState_NotInstalled():
return notInstalled();}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( BridgeBootstrapSessionIdentity identity)?  running,TResult? Function()?  noSession,TResult? Function()?  notInstalled,}) {final _that = this;
switch (_that) {
case BridgeBootstrapSessionState_Running() when running != null:
return running(_that.identity);case BridgeBootstrapSessionState_NoSession() when noSession != null:
return noSession();case BridgeBootstrapSessionState_NotInstalled() when notInstalled != null:
return notInstalled();case _:
  return null;

}
}

}

/// @nodoc


class BridgeBootstrapSessionState_Running extends BridgeBootstrapSessionState {
  const BridgeBootstrapSessionState_Running({required this.identity}): super._();
  

 final  BridgeBootstrapSessionIdentity identity;

/// Create a copy of BridgeBootstrapSessionState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeBootstrapSessionState_RunningCopyWith<BridgeBootstrapSessionState_Running> get copyWith => _$BridgeBootstrapSessionState_RunningCopyWithImpl<BridgeBootstrapSessionState_Running>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeBootstrapSessionState_Running&&(identical(other.identity, identity) || other.identity == identity));
}


@override
int get hashCode => Object.hash(runtimeType,identity);

@override
String toString() {
  return 'BridgeBootstrapSessionState.running(identity: $identity)';
}


}

/// @nodoc
abstract mixin class $BridgeBootstrapSessionState_RunningCopyWith<$Res> implements $BridgeBootstrapSessionStateCopyWith<$Res> {
  factory $BridgeBootstrapSessionState_RunningCopyWith(BridgeBootstrapSessionState_Running value, $Res Function(BridgeBootstrapSessionState_Running) _then) = _$BridgeBootstrapSessionState_RunningCopyWithImpl;
@useResult
$Res call({
 BridgeBootstrapSessionIdentity identity
});




}
/// @nodoc
class _$BridgeBootstrapSessionState_RunningCopyWithImpl<$Res>
    implements $BridgeBootstrapSessionState_RunningCopyWith<$Res> {
  _$BridgeBootstrapSessionState_RunningCopyWithImpl(this._self, this._then);

  final BridgeBootstrapSessionState_Running _self;
  final $Res Function(BridgeBootstrapSessionState_Running) _then;

/// Create a copy of BridgeBootstrapSessionState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? identity = null,}) {
  return _then(BridgeBootstrapSessionState_Running(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as BridgeBootstrapSessionIdentity,
  ));
}


}

/// @nodoc


class BridgeBootstrapSessionState_NoSession extends BridgeBootstrapSessionState {
  const BridgeBootstrapSessionState_NoSession(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeBootstrapSessionState_NoSession);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'BridgeBootstrapSessionState.noSession()';
}


}




/// @nodoc


class BridgeBootstrapSessionState_NotInstalled extends BridgeBootstrapSessionState {
  const BridgeBootstrapSessionState_NotInstalled(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeBootstrapSessionState_NotInstalled);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'BridgeBootstrapSessionState.notInstalled()';
}


}




/// @nodoc
mixin _$BridgeBootstrapSource {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeBootstrapSource);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'BridgeBootstrapSource()';
}


}

/// @nodoc
class $BridgeBootstrapSourceCopyWith<$Res>  {
$BridgeBootstrapSourceCopyWith(BridgeBootstrapSource _, $Res Function(BridgeBootstrapSource) __);
}


/// Adds pattern-matching-related methods to [BridgeBootstrapSource].
extension BridgeBootstrapSourcePatterns on BridgeBootstrapSource {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeBootstrapSource_Override value)?  override,TResult Function( BridgeBootstrapSource_Sibling value)?  sibling,TResult Function( BridgeBootstrapSource_Asset value)?  asset,TResult Function( BridgeBootstrapSource_None value)?  none,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeBootstrapSource_Override() when override != null:
return override(_that);case BridgeBootstrapSource_Sibling() when sibling != null:
return sibling(_that);case BridgeBootstrapSource_Asset() when asset != null:
return asset(_that);case BridgeBootstrapSource_None() when none != null:
return none(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeBootstrapSource_Override value)  override,required TResult Function( BridgeBootstrapSource_Sibling value)  sibling,required TResult Function( BridgeBootstrapSource_Asset value)  asset,required TResult Function( BridgeBootstrapSource_None value)  none,}){
final _that = this;
switch (_that) {
case BridgeBootstrapSource_Override():
return override(_that);case BridgeBootstrapSource_Sibling():
return sibling(_that);case BridgeBootstrapSource_Asset():
return asset(_that);case BridgeBootstrapSource_None():
return none(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeBootstrapSource_Override value)?  override,TResult? Function( BridgeBootstrapSource_Sibling value)?  sibling,TResult? Function( BridgeBootstrapSource_Asset value)?  asset,TResult? Function( BridgeBootstrapSource_None value)?  none,}){
final _that = this;
switch (_that) {
case BridgeBootstrapSource_Override() when override != null:
return override(_that);case BridgeBootstrapSource_Sibling() when sibling != null:
return sibling(_that);case BridgeBootstrapSource_Asset() when asset != null:
return asset(_that);case BridgeBootstrapSource_None() when none != null:
return none(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String path)?  override,TResult Function( String path)?  sibling,TResult Function( String base,  String version)?  asset,TResult Function()?  none,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeBootstrapSource_Override() when override != null:
return override(_that.path);case BridgeBootstrapSource_Sibling() when sibling != null:
return sibling(_that.path);case BridgeBootstrapSource_Asset() when asset != null:
return asset(_that.base,_that.version);case BridgeBootstrapSource_None() when none != null:
return none();case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String path)  override,required TResult Function( String path)  sibling,required TResult Function( String base,  String version)  asset,required TResult Function()  none,}) {final _that = this;
switch (_that) {
case BridgeBootstrapSource_Override():
return override(_that.path);case BridgeBootstrapSource_Sibling():
return sibling(_that.path);case BridgeBootstrapSource_Asset():
return asset(_that.base,_that.version);case BridgeBootstrapSource_None():
return none();}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String path)?  override,TResult? Function( String path)?  sibling,TResult? Function( String base,  String version)?  asset,TResult? Function()?  none,}) {final _that = this;
switch (_that) {
case BridgeBootstrapSource_Override() when override != null:
return override(_that.path);case BridgeBootstrapSource_Sibling() when sibling != null:
return sibling(_that.path);case BridgeBootstrapSource_Asset() when asset != null:
return asset(_that.base,_that.version);case BridgeBootstrapSource_None() when none != null:
return none();case _:
  return null;

}
}

}

/// @nodoc


class BridgeBootstrapSource_Override extends BridgeBootstrapSource {
  const BridgeBootstrapSource_Override({required this.path}): super._();
  

 final  String path;

/// Create a copy of BridgeBootstrapSource
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeBootstrapSource_OverrideCopyWith<BridgeBootstrapSource_Override> get copyWith => _$BridgeBootstrapSource_OverrideCopyWithImpl<BridgeBootstrapSource_Override>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeBootstrapSource_Override&&(identical(other.path, path) || other.path == path));
}


@override
int get hashCode => Object.hash(runtimeType,path);

@override
String toString() {
  return 'BridgeBootstrapSource.override(path: $path)';
}


}

/// @nodoc
abstract mixin class $BridgeBootstrapSource_OverrideCopyWith<$Res> implements $BridgeBootstrapSourceCopyWith<$Res> {
  factory $BridgeBootstrapSource_OverrideCopyWith(BridgeBootstrapSource_Override value, $Res Function(BridgeBootstrapSource_Override) _then) = _$BridgeBootstrapSource_OverrideCopyWithImpl;
@useResult
$Res call({
 String path
});




}
/// @nodoc
class _$BridgeBootstrapSource_OverrideCopyWithImpl<$Res>
    implements $BridgeBootstrapSource_OverrideCopyWith<$Res> {
  _$BridgeBootstrapSource_OverrideCopyWithImpl(this._self, this._then);

  final BridgeBootstrapSource_Override _self;
  final $Res Function(BridgeBootstrapSource_Override) _then;

/// Create a copy of BridgeBootstrapSource
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? path = null,}) {
  return _then(BridgeBootstrapSource_Override(
path: null == path ? _self.path : path // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class BridgeBootstrapSource_Sibling extends BridgeBootstrapSource {
  const BridgeBootstrapSource_Sibling({required this.path}): super._();
  

 final  String path;

/// Create a copy of BridgeBootstrapSource
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeBootstrapSource_SiblingCopyWith<BridgeBootstrapSource_Sibling> get copyWith => _$BridgeBootstrapSource_SiblingCopyWithImpl<BridgeBootstrapSource_Sibling>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeBootstrapSource_Sibling&&(identical(other.path, path) || other.path == path));
}


@override
int get hashCode => Object.hash(runtimeType,path);

@override
String toString() {
  return 'BridgeBootstrapSource.sibling(path: $path)';
}


}

/// @nodoc
abstract mixin class $BridgeBootstrapSource_SiblingCopyWith<$Res> implements $BridgeBootstrapSourceCopyWith<$Res> {
  factory $BridgeBootstrapSource_SiblingCopyWith(BridgeBootstrapSource_Sibling value, $Res Function(BridgeBootstrapSource_Sibling) _then) = _$BridgeBootstrapSource_SiblingCopyWithImpl;
@useResult
$Res call({
 String path
});




}
/// @nodoc
class _$BridgeBootstrapSource_SiblingCopyWithImpl<$Res>
    implements $BridgeBootstrapSource_SiblingCopyWith<$Res> {
  _$BridgeBootstrapSource_SiblingCopyWithImpl(this._self, this._then);

  final BridgeBootstrapSource_Sibling _self;
  final $Res Function(BridgeBootstrapSource_Sibling) _then;

/// Create a copy of BridgeBootstrapSource
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? path = null,}) {
  return _then(BridgeBootstrapSource_Sibling(
path: null == path ? _self.path : path // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class BridgeBootstrapSource_Asset extends BridgeBootstrapSource {
  const BridgeBootstrapSource_Asset({required this.base, required this.version}): super._();
  

 final  String base;
 final  String version;

/// Create a copy of BridgeBootstrapSource
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeBootstrapSource_AssetCopyWith<BridgeBootstrapSource_Asset> get copyWith => _$BridgeBootstrapSource_AssetCopyWithImpl<BridgeBootstrapSource_Asset>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeBootstrapSource_Asset&&(identical(other.base, base) || other.base == base)&&(identical(other.version, version) || other.version == version));
}


@override
int get hashCode => Object.hash(runtimeType,base,version);

@override
String toString() {
  return 'BridgeBootstrapSource.asset(base: $base, version: $version)';
}


}

/// @nodoc
abstract mixin class $BridgeBootstrapSource_AssetCopyWith<$Res> implements $BridgeBootstrapSourceCopyWith<$Res> {
  factory $BridgeBootstrapSource_AssetCopyWith(BridgeBootstrapSource_Asset value, $Res Function(BridgeBootstrapSource_Asset) _then) = _$BridgeBootstrapSource_AssetCopyWithImpl;
@useResult
$Res call({
 String base, String version
});




}
/// @nodoc
class _$BridgeBootstrapSource_AssetCopyWithImpl<$Res>
    implements $BridgeBootstrapSource_AssetCopyWith<$Res> {
  _$BridgeBootstrapSource_AssetCopyWithImpl(this._self, this._then);

  final BridgeBootstrapSource_Asset _self;
  final $Res Function(BridgeBootstrapSource_Asset) _then;

/// Create a copy of BridgeBootstrapSource
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? base = null,Object? version = null,}) {
  return _then(BridgeBootstrapSource_Asset(
base: null == base ? _self.base : base // ignore: cast_nullable_to_non_nullable
as String,version: null == version ? _self.version : version // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class BridgeBootstrapSource_None extends BridgeBootstrapSource {
  const BridgeBootstrapSource_None(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeBootstrapSource_None);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'BridgeBootstrapSource.none()';
}


}




/// @nodoc
mixin _$BridgeBootstrapStdin {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeBootstrapStdin);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'BridgeBootstrapStdin()';
}


}

/// @nodoc
class $BridgeBootstrapStdinCopyWith<$Res>  {
$BridgeBootstrapStdinCopyWith(BridgeBootstrapStdin _, $Res Function(BridgeBootstrapStdin) __);
}


/// Adds pattern-matching-related methods to [BridgeBootstrapStdin].
extension BridgeBootstrapStdinPatterns on BridgeBootstrapStdin {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeBootstrapStdin_Empty value)?  empty,TResult Function( BridgeBootstrapStdin_Bytes value)?  bytes,TResult Function( BridgeBootstrapStdin_Source value)?  source,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeBootstrapStdin_Empty() when empty != null:
return empty(_that);case BridgeBootstrapStdin_Bytes() when bytes != null:
return bytes(_that);case BridgeBootstrapStdin_Source() when source != null:
return source(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeBootstrapStdin_Empty value)  empty,required TResult Function( BridgeBootstrapStdin_Bytes value)  bytes,required TResult Function( BridgeBootstrapStdin_Source value)  source,}){
final _that = this;
switch (_that) {
case BridgeBootstrapStdin_Empty():
return empty(_that);case BridgeBootstrapStdin_Bytes():
return bytes(_that);case BridgeBootstrapStdin_Source():
return source(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeBootstrapStdin_Empty value)?  empty,TResult? Function( BridgeBootstrapStdin_Bytes value)?  bytes,TResult? Function( BridgeBootstrapStdin_Source value)?  source,}){
final _that = this;
switch (_that) {
case BridgeBootstrapStdin_Empty() when empty != null:
return empty(_that);case BridgeBootstrapStdin_Bytes() when bytes != null:
return bytes(_that);case BridgeBootstrapStdin_Source() when source != null:
return source(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  empty,TResult Function( Uint8List bytes)?  bytes,TResult Function( BigInt len,  String origin,  String? sha256)?  source,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeBootstrapStdin_Empty() when empty != null:
return empty();case BridgeBootstrapStdin_Bytes() when bytes != null:
return bytes(_that.bytes);case BridgeBootstrapStdin_Source() when source != null:
return source(_that.len,_that.origin,_that.sha256);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  empty,required TResult Function( Uint8List bytes)  bytes,required TResult Function( BigInt len,  String origin,  String? sha256)  source,}) {final _that = this;
switch (_that) {
case BridgeBootstrapStdin_Empty():
return empty();case BridgeBootstrapStdin_Bytes():
return bytes(_that.bytes);case BridgeBootstrapStdin_Source():
return source(_that.len,_that.origin,_that.sha256);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  empty,TResult? Function( Uint8List bytes)?  bytes,TResult? Function( BigInt len,  String origin,  String? sha256)?  source,}) {final _that = this;
switch (_that) {
case BridgeBootstrapStdin_Empty() when empty != null:
return empty();case BridgeBootstrapStdin_Bytes() when bytes != null:
return bytes(_that.bytes);case BridgeBootstrapStdin_Source() when source != null:
return source(_that.len,_that.origin,_that.sha256);case _:
  return null;

}
}

}

/// @nodoc


class BridgeBootstrapStdin_Empty extends BridgeBootstrapStdin {
  const BridgeBootstrapStdin_Empty(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeBootstrapStdin_Empty);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'BridgeBootstrapStdin.empty()';
}


}




/// @nodoc


class BridgeBootstrapStdin_Bytes extends BridgeBootstrapStdin {
  const BridgeBootstrapStdin_Bytes({required this.bytes}): super._();
  

 final  Uint8List bytes;

/// Create a copy of BridgeBootstrapStdin
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeBootstrapStdin_BytesCopyWith<BridgeBootstrapStdin_Bytes> get copyWith => _$BridgeBootstrapStdin_BytesCopyWithImpl<BridgeBootstrapStdin_Bytes>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeBootstrapStdin_Bytes&&const DeepCollectionEquality().equals(other.bytes, bytes));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(bytes));

@override
String toString() {
  return 'BridgeBootstrapStdin.bytes(bytes: $bytes)';
}


}

/// @nodoc
abstract mixin class $BridgeBootstrapStdin_BytesCopyWith<$Res> implements $BridgeBootstrapStdinCopyWith<$Res> {
  factory $BridgeBootstrapStdin_BytesCopyWith(BridgeBootstrapStdin_Bytes value, $Res Function(BridgeBootstrapStdin_Bytes) _then) = _$BridgeBootstrapStdin_BytesCopyWithImpl;
@useResult
$Res call({
 Uint8List bytes
});




}
/// @nodoc
class _$BridgeBootstrapStdin_BytesCopyWithImpl<$Res>
    implements $BridgeBootstrapStdin_BytesCopyWith<$Res> {
  _$BridgeBootstrapStdin_BytesCopyWithImpl(this._self, this._then);

  final BridgeBootstrapStdin_Bytes _self;
  final $Res Function(BridgeBootstrapStdin_Bytes) _then;

/// Create a copy of BridgeBootstrapStdin
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? bytes = null,}) {
  return _then(BridgeBootstrapStdin_Bytes(
bytes: null == bytes ? _self.bytes : bytes // ignore: cast_nullable_to_non_nullable
as Uint8List,
  ));
}


}

/// @nodoc


class BridgeBootstrapStdin_Source extends BridgeBootstrapStdin {
  const BridgeBootstrapStdin_Source({required this.len, required this.origin, this.sha256}): super._();
  

/// How many bytes there are, for a progress line.
 final  BigInt len;
/// Where they came from — the same sentence the consent sheet showed.
 final  String origin;
/// The hex sha256 the ladder verified, when there was a published one to
/// verify against.
 final  String? sha256;

/// Create a copy of BridgeBootstrapStdin
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeBootstrapStdin_SourceCopyWith<BridgeBootstrapStdin_Source> get copyWith => _$BridgeBootstrapStdin_SourceCopyWithImpl<BridgeBootstrapStdin_Source>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeBootstrapStdin_Source&&(identical(other.len, len) || other.len == len)&&(identical(other.origin, origin) || other.origin == origin)&&(identical(other.sha256, sha256) || other.sha256 == sha256));
}


@override
int get hashCode => Object.hash(runtimeType,len,origin,sha256);

@override
String toString() {
  return 'BridgeBootstrapStdin.source(len: $len, origin: $origin, sha256: $sha256)';
}


}

/// @nodoc
abstract mixin class $BridgeBootstrapStdin_SourceCopyWith<$Res> implements $BridgeBootstrapStdinCopyWith<$Res> {
  factory $BridgeBootstrapStdin_SourceCopyWith(BridgeBootstrapStdin_Source value, $Res Function(BridgeBootstrapStdin_Source) _then) = _$BridgeBootstrapStdin_SourceCopyWithImpl;
@useResult
$Res call({
 BigInt len, String origin, String? sha256
});




}
/// @nodoc
class _$BridgeBootstrapStdin_SourceCopyWithImpl<$Res>
    implements $BridgeBootstrapStdin_SourceCopyWith<$Res> {
  _$BridgeBootstrapStdin_SourceCopyWithImpl(this._self, this._then);

  final BridgeBootstrapStdin_Source _self;
  final $Res Function(BridgeBootstrapStdin_Source) _then;

/// Create a copy of BridgeBootstrapStdin
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? len = null,Object? origin = null,Object? sha256 = freezed,}) {
  return _then(BridgeBootstrapStdin_Source(
len: null == len ? _self.len : len // ignore: cast_nullable_to_non_nullable
as BigInt,origin: null == origin ? _self.origin : origin // ignore: cast_nullable_to_non_nullable
as String,sha256: freezed == sha256 ? _self.sha256 : sha256 // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

/// @nodoc
mixin _$BridgeBootstrapStep {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeBootstrapStep);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'BridgeBootstrapStep()';
}


}

/// @nodoc
class $BridgeBootstrapStepCopyWith<$Res>  {
$BridgeBootstrapStepCopyWith(BridgeBootstrapStep _, $Res Function(BridgeBootstrapStep) __);
}


/// Adds pattern-matching-related methods to [BridgeBootstrapStep].
extension BridgeBootstrapStepPatterns on BridgeBootstrapStep {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeBootstrapStep_Exec value)?  exec,TResult Function( BridgeBootstrapStep_Probed value)?  probed,TResult Function( BridgeBootstrapStep_Installed value)?  installed,TResult Function( BridgeBootstrapStep_Failed value)?  failed,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeBootstrapStep_Exec() when exec != null:
return exec(_that);case BridgeBootstrapStep_Probed() when probed != null:
return probed(_that);case BridgeBootstrapStep_Installed() when installed != null:
return installed(_that);case BridgeBootstrapStep_Failed() when failed != null:
return failed(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeBootstrapStep_Exec value)  exec,required TResult Function( BridgeBootstrapStep_Probed value)  probed,required TResult Function( BridgeBootstrapStep_Installed value)  installed,required TResult Function( BridgeBootstrapStep_Failed value)  failed,}){
final _that = this;
switch (_that) {
case BridgeBootstrapStep_Exec():
return exec(_that);case BridgeBootstrapStep_Probed():
return probed(_that);case BridgeBootstrapStep_Installed():
return installed(_that);case BridgeBootstrapStep_Failed():
return failed(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeBootstrapStep_Exec value)?  exec,TResult? Function( BridgeBootstrapStep_Probed value)?  probed,TResult? Function( BridgeBootstrapStep_Installed value)?  installed,TResult? Function( BridgeBootstrapStep_Failed value)?  failed,}){
final _that = this;
switch (_that) {
case BridgeBootstrapStep_Exec() when exec != null:
return exec(_that);case BridgeBootstrapStep_Probed() when probed != null:
return probed(_that);case BridgeBootstrapStep_Installed() when installed != null:
return installed(_that);case BridgeBootstrapStep_Failed() when failed != null:
return failed(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String command,  BridgeBootstrapStdin stdin,  int budgetMs,  int stdoutCap,  bool captureStdout,  int stderrCap)?  exec,TResult Function( BridgeBootstrapProbe probe)?  probed,TResult Function( BridgeBootstrapInstalled installed)?  installed,TResult Function( BridgeBootstrapFailure failure)?  failed,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeBootstrapStep_Exec() when exec != null:
return exec(_that.command,_that.stdin,_that.budgetMs,_that.stdoutCap,_that.captureStdout,_that.stderrCap);case BridgeBootstrapStep_Probed() when probed != null:
return probed(_that.probe);case BridgeBootstrapStep_Installed() when installed != null:
return installed(_that.installed);case BridgeBootstrapStep_Failed() when failed != null:
return failed(_that.failure);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String command,  BridgeBootstrapStdin stdin,  int budgetMs,  int stdoutCap,  bool captureStdout,  int stderrCap)  exec,required TResult Function( BridgeBootstrapProbe probe)  probed,required TResult Function( BridgeBootstrapInstalled installed)  installed,required TResult Function( BridgeBootstrapFailure failure)  failed,}) {final _that = this;
switch (_that) {
case BridgeBootstrapStep_Exec():
return exec(_that.command,_that.stdin,_that.budgetMs,_that.stdoutCap,_that.captureStdout,_that.stderrCap);case BridgeBootstrapStep_Probed():
return probed(_that.probe);case BridgeBootstrapStep_Installed():
return installed(_that.installed);case BridgeBootstrapStep_Failed():
return failed(_that.failure);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String command,  BridgeBootstrapStdin stdin,  int budgetMs,  int stdoutCap,  bool captureStdout,  int stderrCap)?  exec,TResult? Function( BridgeBootstrapProbe probe)?  probed,TResult? Function( BridgeBootstrapInstalled installed)?  installed,TResult? Function( BridgeBootstrapFailure failure)?  failed,}) {final _that = this;
switch (_that) {
case BridgeBootstrapStep_Exec() when exec != null:
return exec(_that.command,_that.stdin,_that.budgetMs,_that.stdoutCap,_that.captureStdout,_that.stderrCap);case BridgeBootstrapStep_Probed() when probed != null:
return probed(_that.probe);case BridgeBootstrapStep_Installed() when installed != null:
return installed(_that.installed);case BridgeBootstrapStep_Failed() when failed != null:
return failed(_that.failure);case _:
  return null;

}
}

}

/// @nodoc


class BridgeBootstrapStep_Exec extends BridgeBootstrapStep {
  const BridgeBootstrapStep_Exec({required this.command, required this.stdin, required this.budgetMs, required this.stdoutCap, required this.captureStdout, required this.stderrCap}): super._();
  

 final  String command;
 final  BridgeBootstrapStdin stdin;
/// How long this step may take, in milliseconds. Every one of shed-core's
/// budgets is seconds-to-minutes, so it fits an `int` on the Dart side
/// rather than costing a `BigInt` at every call.
 final  int budgetMs;
/// Keep at most this many bytes of stdout, from the **head** — the
/// answers that matter are NUL-delimited records at the start.
 final  int stdoutCap;
/// `false` for a [`BridgeBootstrapStdin::Source`] step: `tee` echoes
/// every byte it is fed, and buffering a 10 MiB binary back into memory
/// to look at a stdout nothing reads would be absurd. Discard it, do not
/// merely cap it.
 final  bool captureStdout;
/// Keep at most this many bytes of stderr, from the **tail** — the
/// opposite end from `stdout_cap`, because one line of it reaches the
/// user and the useful line is the last one.
///
/// **Carried rather than left to the runner to invent.** shed-core's
/// `Step::Exec` does not name a stderr cap — it is the client's choice,
/// and the desktop makes its own ([`STDERR_TAIL_CAP`], 4 KiB, private to
/// `shed-app`). A Dart runner with no value here would pick a second
/// number, and the two clients would then truncate the same failure
/// differently for no reason anybody could find later. So the number
/// crosses with the other two caps, from [`STDERR_TAIL_CAP`] below.
 final  int stderrCap;

/// Create a copy of BridgeBootstrapStep
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeBootstrapStep_ExecCopyWith<BridgeBootstrapStep_Exec> get copyWith => _$BridgeBootstrapStep_ExecCopyWithImpl<BridgeBootstrapStep_Exec>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeBootstrapStep_Exec&&(identical(other.command, command) || other.command == command)&&(identical(other.stdin, stdin) || other.stdin == stdin)&&(identical(other.budgetMs, budgetMs) || other.budgetMs == budgetMs)&&(identical(other.stdoutCap, stdoutCap) || other.stdoutCap == stdoutCap)&&(identical(other.captureStdout, captureStdout) || other.captureStdout == captureStdout)&&(identical(other.stderrCap, stderrCap) || other.stderrCap == stderrCap));
}


@override
int get hashCode => Object.hash(runtimeType,command,stdin,budgetMs,stdoutCap,captureStdout,stderrCap);

@override
String toString() {
  return 'BridgeBootstrapStep.exec(command: $command, stdin: $stdin, budgetMs: $budgetMs, stdoutCap: $stdoutCap, captureStdout: $captureStdout, stderrCap: $stderrCap)';
}


}

/// @nodoc
abstract mixin class $BridgeBootstrapStep_ExecCopyWith<$Res> implements $BridgeBootstrapStepCopyWith<$Res> {
  factory $BridgeBootstrapStep_ExecCopyWith(BridgeBootstrapStep_Exec value, $Res Function(BridgeBootstrapStep_Exec) _then) = _$BridgeBootstrapStep_ExecCopyWithImpl;
@useResult
$Res call({
 String command, BridgeBootstrapStdin stdin, int budgetMs, int stdoutCap, bool captureStdout, int stderrCap
});


$BridgeBootstrapStdinCopyWith<$Res> get stdin;

}
/// @nodoc
class _$BridgeBootstrapStep_ExecCopyWithImpl<$Res>
    implements $BridgeBootstrapStep_ExecCopyWith<$Res> {
  _$BridgeBootstrapStep_ExecCopyWithImpl(this._self, this._then);

  final BridgeBootstrapStep_Exec _self;
  final $Res Function(BridgeBootstrapStep_Exec) _then;

/// Create a copy of BridgeBootstrapStep
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? command = null,Object? stdin = null,Object? budgetMs = null,Object? stdoutCap = null,Object? captureStdout = null,Object? stderrCap = null,}) {
  return _then(BridgeBootstrapStep_Exec(
command: null == command ? _self.command : command // ignore: cast_nullable_to_non_nullable
as String,stdin: null == stdin ? _self.stdin : stdin // ignore: cast_nullable_to_non_nullable
as BridgeBootstrapStdin,budgetMs: null == budgetMs ? _self.budgetMs : budgetMs // ignore: cast_nullable_to_non_nullable
as int,stdoutCap: null == stdoutCap ? _self.stdoutCap : stdoutCap // ignore: cast_nullable_to_non_nullable
as int,captureStdout: null == captureStdout ? _self.captureStdout : captureStdout // ignore: cast_nullable_to_non_nullable
as bool,stderrCap: null == stderrCap ? _self.stderrCap : stderrCap // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

/// Create a copy of BridgeBootstrapStep
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BridgeBootstrapStdinCopyWith<$Res> get stdin {
  
  return $BridgeBootstrapStdinCopyWith<$Res>(_self.stdin, (value) {
    return _then(_self.copyWith(stdin: value));
  });
}
}

/// @nodoc


class BridgeBootstrapStep_Probed extends BridgeBootstrapStep {
  const BridgeBootstrapStep_Probed({required this.probe}): super._();
  

 final  BridgeBootstrapProbe probe;

/// Create a copy of BridgeBootstrapStep
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeBootstrapStep_ProbedCopyWith<BridgeBootstrapStep_Probed> get copyWith => _$BridgeBootstrapStep_ProbedCopyWithImpl<BridgeBootstrapStep_Probed>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeBootstrapStep_Probed&&(identical(other.probe, probe) || other.probe == probe));
}


@override
int get hashCode => Object.hash(runtimeType,probe);

@override
String toString() {
  return 'BridgeBootstrapStep.probed(probe: $probe)';
}


}

/// @nodoc
abstract mixin class $BridgeBootstrapStep_ProbedCopyWith<$Res> implements $BridgeBootstrapStepCopyWith<$Res> {
  factory $BridgeBootstrapStep_ProbedCopyWith(BridgeBootstrapStep_Probed value, $Res Function(BridgeBootstrapStep_Probed) _then) = _$BridgeBootstrapStep_ProbedCopyWithImpl;
@useResult
$Res call({
 BridgeBootstrapProbe probe
});




}
/// @nodoc
class _$BridgeBootstrapStep_ProbedCopyWithImpl<$Res>
    implements $BridgeBootstrapStep_ProbedCopyWith<$Res> {
  _$BridgeBootstrapStep_ProbedCopyWithImpl(this._self, this._then);

  final BridgeBootstrapStep_Probed _self;
  final $Res Function(BridgeBootstrapStep_Probed) _then;

/// Create a copy of BridgeBootstrapStep
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? probe = null,}) {
  return _then(BridgeBootstrapStep_Probed(
probe: null == probe ? _self.probe : probe // ignore: cast_nullable_to_non_nullable
as BridgeBootstrapProbe,
  ));
}


}

/// @nodoc


class BridgeBootstrapStep_Installed extends BridgeBootstrapStep {
  const BridgeBootstrapStep_Installed({required this.installed}): super._();
  

 final  BridgeBootstrapInstalled installed;

/// Create a copy of BridgeBootstrapStep
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeBootstrapStep_InstalledCopyWith<BridgeBootstrapStep_Installed> get copyWith => _$BridgeBootstrapStep_InstalledCopyWithImpl<BridgeBootstrapStep_Installed>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeBootstrapStep_Installed&&(identical(other.installed, installed) || other.installed == installed));
}


@override
int get hashCode => Object.hash(runtimeType,installed);

@override
String toString() {
  return 'BridgeBootstrapStep.installed(installed: $installed)';
}


}

/// @nodoc
abstract mixin class $BridgeBootstrapStep_InstalledCopyWith<$Res> implements $BridgeBootstrapStepCopyWith<$Res> {
  factory $BridgeBootstrapStep_InstalledCopyWith(BridgeBootstrapStep_Installed value, $Res Function(BridgeBootstrapStep_Installed) _then) = _$BridgeBootstrapStep_InstalledCopyWithImpl;
@useResult
$Res call({
 BridgeBootstrapInstalled installed
});




}
/// @nodoc
class _$BridgeBootstrapStep_InstalledCopyWithImpl<$Res>
    implements $BridgeBootstrapStep_InstalledCopyWith<$Res> {
  _$BridgeBootstrapStep_InstalledCopyWithImpl(this._self, this._then);

  final BridgeBootstrapStep_Installed _self;
  final $Res Function(BridgeBootstrapStep_Installed) _then;

/// Create a copy of BridgeBootstrapStep
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? installed = null,}) {
  return _then(BridgeBootstrapStep_Installed(
installed: null == installed ? _self.installed : installed // ignore: cast_nullable_to_non_nullable
as BridgeBootstrapInstalled,
  ));
}


}

/// @nodoc


class BridgeBootstrapStep_Failed extends BridgeBootstrapStep {
  const BridgeBootstrapStep_Failed({required this.failure}): super._();
  

 final  BridgeBootstrapFailure failure;

/// Create a copy of BridgeBootstrapStep
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeBootstrapStep_FailedCopyWith<BridgeBootstrapStep_Failed> get copyWith => _$BridgeBootstrapStep_FailedCopyWithImpl<BridgeBootstrapStep_Failed>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeBootstrapStep_Failed&&(identical(other.failure, failure) || other.failure == failure));
}


@override
int get hashCode => Object.hash(runtimeType,failure);

@override
String toString() {
  return 'BridgeBootstrapStep.failed(failure: $failure)';
}


}

/// @nodoc
abstract mixin class $BridgeBootstrapStep_FailedCopyWith<$Res> implements $BridgeBootstrapStepCopyWith<$Res> {
  factory $BridgeBootstrapStep_FailedCopyWith(BridgeBootstrapStep_Failed value, $Res Function(BridgeBootstrapStep_Failed) _then) = _$BridgeBootstrapStep_FailedCopyWithImpl;
@useResult
$Res call({
 BridgeBootstrapFailure failure
});




}
/// @nodoc
class _$BridgeBootstrapStep_FailedCopyWithImpl<$Res>
    implements $BridgeBootstrapStep_FailedCopyWith<$Res> {
  _$BridgeBootstrapStep_FailedCopyWithImpl(this._self, this._then);

  final BridgeBootstrapStep_Failed _self;
  final $Res Function(BridgeBootstrapStep_Failed) _then;

/// Create a copy of BridgeBootstrapStep
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? failure = null,}) {
  return _then(BridgeBootstrapStep_Failed(
failure: null == failure ? _self.failure : failure // ignore: cast_nullable_to_non_nullable
as BridgeBootstrapFailure,
  ));
}


}

// dart format on

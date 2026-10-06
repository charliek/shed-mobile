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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeRcKind_ClaudeRc value)?  claudeRc,TResult Function( BridgeRcKind_ClaudeBroker value)?  claudeBroker,TResult Function( BridgeRcKind_Opencode value)?  opencode,TResult Function( BridgeRcKind_Craze value)?  craze,TResult Function( BridgeRcKind_Shell value)?  shell,TResult Function( BridgeRcKind_Other value)?  other,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeRcKind_ClaudeRc() when claudeRc != null:
return claudeRc(_that);case BridgeRcKind_ClaudeBroker() when claudeBroker != null:
return claudeBroker(_that);case BridgeRcKind_Opencode() when opencode != null:
return opencode(_that);case BridgeRcKind_Craze() when craze != null:
return craze(_that);case BridgeRcKind_Shell() when shell != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeRcKind_ClaudeRc value)  claudeRc,required TResult Function( BridgeRcKind_ClaudeBroker value)  claudeBroker,required TResult Function( BridgeRcKind_Opencode value)  opencode,required TResult Function( BridgeRcKind_Craze value)  craze,required TResult Function( BridgeRcKind_Shell value)  shell,required TResult Function( BridgeRcKind_Other value)  other,}){
final _that = this;
switch (_that) {
case BridgeRcKind_ClaudeRc():
return claudeRc(_that);case BridgeRcKind_ClaudeBroker():
return claudeBroker(_that);case BridgeRcKind_Opencode():
return opencode(_that);case BridgeRcKind_Craze():
return craze(_that);case BridgeRcKind_Shell():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeRcKind_ClaudeRc value)?  claudeRc,TResult? Function( BridgeRcKind_ClaudeBroker value)?  claudeBroker,TResult? Function( BridgeRcKind_Opencode value)?  opencode,TResult? Function( BridgeRcKind_Craze value)?  craze,TResult? Function( BridgeRcKind_Shell value)?  shell,TResult? Function( BridgeRcKind_Other value)?  other,}){
final _that = this;
switch (_that) {
case BridgeRcKind_ClaudeRc() when claudeRc != null:
return claudeRc(_that);case BridgeRcKind_ClaudeBroker() when claudeBroker != null:
return claudeBroker(_that);case BridgeRcKind_Opencode() when opencode != null:
return opencode(_that);case BridgeRcKind_Craze() when craze != null:
return craze(_that);case BridgeRcKind_Shell() when shell != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  claudeRc,TResult Function()?  claudeBroker,TResult Function()?  opencode,TResult Function()?  craze,TResult Function()?  shell,TResult Function( String raw)?  other,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeRcKind_ClaudeRc() when claudeRc != null:
return claudeRc();case BridgeRcKind_ClaudeBroker() when claudeBroker != null:
return claudeBroker();case BridgeRcKind_Opencode() when opencode != null:
return opencode();case BridgeRcKind_Craze() when craze != null:
return craze();case BridgeRcKind_Shell() when shell != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  claudeRc,required TResult Function()  claudeBroker,required TResult Function()  opencode,required TResult Function()  craze,required TResult Function()  shell,required TResult Function( String raw)  other,}) {final _that = this;
switch (_that) {
case BridgeRcKind_ClaudeRc():
return claudeRc();case BridgeRcKind_ClaudeBroker():
return claudeBroker();case BridgeRcKind_Opencode():
return opencode();case BridgeRcKind_Craze():
return craze();case BridgeRcKind_Shell():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  claudeRc,TResult? Function()?  claudeBroker,TResult? Function()?  opencode,TResult? Function()?  craze,TResult? Function()?  shell,TResult? Function( String raw)?  other,}) {final _that = this;
switch (_that) {
case BridgeRcKind_ClaudeRc() when claudeRc != null:
return claudeRc();case BridgeRcKind_ClaudeBroker() when claudeBroker != null:
return claudeBroker();case BridgeRcKind_Opencode() when opencode != null:
return opencode();case BridgeRcKind_Craze() when craze != null:
return craze();case BridgeRcKind_Shell() when shell != null:
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


class BridgeRcKind_Craze extends BridgeRcKind {
  const BridgeRcKind_Craze(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeRcKind_Craze);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'BridgeRcKind.craze()';
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

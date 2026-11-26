// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'dto.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$BridgeExtendOutcome {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeExtendOutcome);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'BridgeExtendOutcome()';
}


}

/// @nodoc
class $BridgeExtendOutcomeCopyWith<$Res>  {
$BridgeExtendOutcomeCopyWith(BridgeExtendOutcome _, $Res Function(BridgeExtendOutcome) __);
}


/// Adds pattern-matching-related methods to [BridgeExtendOutcome].
extension BridgeExtendOutcomePatterns on BridgeExtendOutcome {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeExtendOutcome_Extended value)?  extended,TResult Function( BridgeExtendOutcome_Refused value)?  refused,TResult Function( BridgeExtendOutcome_Unknown value)?  unknown,TResult Function( BridgeExtendOutcome_Pending value)?  pending,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeExtendOutcome_Extended() when extended != null:
return extended(_that);case BridgeExtendOutcome_Refused() when refused != null:
return refused(_that);case BridgeExtendOutcome_Unknown() when unknown != null:
return unknown(_that);case BridgeExtendOutcome_Pending() when pending != null:
return pending(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeExtendOutcome_Extended value)  extended,required TResult Function( BridgeExtendOutcome_Refused value)  refused,required TResult Function( BridgeExtendOutcome_Unknown value)  unknown,required TResult Function( BridgeExtendOutcome_Pending value)  pending,}){
final _that = this;
switch (_that) {
case BridgeExtendOutcome_Extended():
return extended(_that);case BridgeExtendOutcome_Refused():
return refused(_that);case BridgeExtendOutcome_Unknown():
return unknown(_that);case BridgeExtendOutcome_Pending():
return pending(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeExtendOutcome_Extended value)?  extended,TResult? Function( BridgeExtendOutcome_Refused value)?  refused,TResult? Function( BridgeExtendOutcome_Unknown value)?  unknown,TResult? Function( BridgeExtendOutcome_Pending value)?  pending,}){
final _that = this;
switch (_that) {
case BridgeExtendOutcome_Extended() when extended != null:
return extended(_that);case BridgeExtendOutcome_Refused() when refused != null:
return refused(_that);case BridgeExtendOutcome_Unknown() when unknown != null:
return unknown(_that);case BridgeExtendOutcome_Pending() when pending != null:
return pending(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( BridgeShed shed)?  extended,TResult Function( String code,  String reason,  int? status,  String words)?  refused,TResult Function( int hours,  String words)?  unknown,TResult Function( String words)?  pending,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeExtendOutcome_Extended() when extended != null:
return extended(_that.shed);case BridgeExtendOutcome_Refused() when refused != null:
return refused(_that.code,_that.reason,_that.status,_that.words);case BridgeExtendOutcome_Unknown() when unknown != null:
return unknown(_that.hours,_that.words);case BridgeExtendOutcome_Pending() when pending != null:
return pending(_that.words);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( BridgeShed shed)  extended,required TResult Function( String code,  String reason,  int? status,  String words)  refused,required TResult Function( int hours,  String words)  unknown,required TResult Function( String words)  pending,}) {final _that = this;
switch (_that) {
case BridgeExtendOutcome_Extended():
return extended(_that.shed);case BridgeExtendOutcome_Refused():
return refused(_that.code,_that.reason,_that.status,_that.words);case BridgeExtendOutcome_Unknown():
return unknown(_that.hours,_that.words);case BridgeExtendOutcome_Pending():
return pending(_that.words);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( BridgeShed shed)?  extended,TResult? Function( String code,  String reason,  int? status,  String words)?  refused,TResult? Function( int hours,  String words)?  unknown,TResult? Function( String words)?  pending,}) {final _that = this;
switch (_that) {
case BridgeExtendOutcome_Extended() when extended != null:
return extended(_that.shed);case BridgeExtendOutcome_Refused() when refused != null:
return refused(_that.code,_that.reason,_that.status,_that.words);case BridgeExtendOutcome_Unknown() when unknown != null:
return unknown(_that.hours,_that.words);case BridgeExtendOutcome_Pending() when pending != null:
return pending(_that.words);case _:
  return null;

}
}

}

/// @nodoc


class BridgeExtendOutcome_Extended extends BridgeExtendOutcome {
  const BridgeExtendOutcome_Extended({required this.shed}): super._();
  

 final  BridgeShed shed;

/// Create a copy of BridgeExtendOutcome
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeExtendOutcome_ExtendedCopyWith<BridgeExtendOutcome_Extended> get copyWith => _$BridgeExtendOutcome_ExtendedCopyWithImpl<BridgeExtendOutcome_Extended>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeExtendOutcome_Extended&&(identical(other.shed, shed) || other.shed == shed));
}


@override
int get hashCode => Object.hash(runtimeType,shed);

@override
String toString() {
  return 'BridgeExtendOutcome.extended(shed: $shed)';
}


}

/// @nodoc
abstract mixin class $BridgeExtendOutcome_ExtendedCopyWith<$Res> implements $BridgeExtendOutcomeCopyWith<$Res> {
  factory $BridgeExtendOutcome_ExtendedCopyWith(BridgeExtendOutcome_Extended value, $Res Function(BridgeExtendOutcome_Extended) _then) = _$BridgeExtendOutcome_ExtendedCopyWithImpl;
@useResult
$Res call({
 BridgeShed shed
});




}
/// @nodoc
class _$BridgeExtendOutcome_ExtendedCopyWithImpl<$Res>
    implements $BridgeExtendOutcome_ExtendedCopyWith<$Res> {
  _$BridgeExtendOutcome_ExtendedCopyWithImpl(this._self, this._then);

  final BridgeExtendOutcome_Extended _self;
  final $Res Function(BridgeExtendOutcome_Extended) _then;

/// Create a copy of BridgeExtendOutcome
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? shed = null,}) {
  return _then(BridgeExtendOutcome_Extended(
shed: null == shed ? _self.shed : shed // ignore: cast_nullable_to_non_nullable
as BridgeShed,
  ));
}


}

/// @nodoc


class BridgeExtendOutcome_Refused extends BridgeExtendOutcome {
  const BridgeExtendOutcome_Refused({required this.code, required this.reason, this.status, required this.words}): super._();
  

 final  String code;
 final  String reason;
 final  int? status;
 final  String words;

/// Create a copy of BridgeExtendOutcome
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeExtendOutcome_RefusedCopyWith<BridgeExtendOutcome_Refused> get copyWith => _$BridgeExtendOutcome_RefusedCopyWithImpl<BridgeExtendOutcome_Refused>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeExtendOutcome_Refused&&(identical(other.code, code) || other.code == code)&&(identical(other.reason, reason) || other.reason == reason)&&(identical(other.status, status) || other.status == status)&&(identical(other.words, words) || other.words == words));
}


@override
int get hashCode => Object.hash(runtimeType,code,reason,status,words);

@override
String toString() {
  return 'BridgeExtendOutcome.refused(code: $code, reason: $reason, status: $status, words: $words)';
}


}

/// @nodoc
abstract mixin class $BridgeExtendOutcome_RefusedCopyWith<$Res> implements $BridgeExtendOutcomeCopyWith<$Res> {
  factory $BridgeExtendOutcome_RefusedCopyWith(BridgeExtendOutcome_Refused value, $Res Function(BridgeExtendOutcome_Refused) _then) = _$BridgeExtendOutcome_RefusedCopyWithImpl;
@useResult
$Res call({
 String code, String reason, int? status, String words
});




}
/// @nodoc
class _$BridgeExtendOutcome_RefusedCopyWithImpl<$Res>
    implements $BridgeExtendOutcome_RefusedCopyWith<$Res> {
  _$BridgeExtendOutcome_RefusedCopyWithImpl(this._self, this._then);

  final BridgeExtendOutcome_Refused _self;
  final $Res Function(BridgeExtendOutcome_Refused) _then;

/// Create a copy of BridgeExtendOutcome
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? code = null,Object? reason = null,Object? status = freezed,Object? words = null,}) {
  return _then(BridgeExtendOutcome_Refused(
code: null == code ? _self.code : code // ignore: cast_nullable_to_non_nullable
as String,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String,status: freezed == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as int?,words: null == words ? _self.words : words // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class BridgeExtendOutcome_Unknown extends BridgeExtendOutcome {
  const BridgeExtendOutcome_Unknown({required this.hours, required this.words}): super._();
  

 final  int hours;
 final  String words;

/// Create a copy of BridgeExtendOutcome
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeExtendOutcome_UnknownCopyWith<BridgeExtendOutcome_Unknown> get copyWith => _$BridgeExtendOutcome_UnknownCopyWithImpl<BridgeExtendOutcome_Unknown>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeExtendOutcome_Unknown&&(identical(other.hours, hours) || other.hours == hours)&&(identical(other.words, words) || other.words == words));
}


@override
int get hashCode => Object.hash(runtimeType,hours,words);

@override
String toString() {
  return 'BridgeExtendOutcome.unknown(hours: $hours, words: $words)';
}


}

/// @nodoc
abstract mixin class $BridgeExtendOutcome_UnknownCopyWith<$Res> implements $BridgeExtendOutcomeCopyWith<$Res> {
  factory $BridgeExtendOutcome_UnknownCopyWith(BridgeExtendOutcome_Unknown value, $Res Function(BridgeExtendOutcome_Unknown) _then) = _$BridgeExtendOutcome_UnknownCopyWithImpl;
@useResult
$Res call({
 int hours, String words
});




}
/// @nodoc
class _$BridgeExtendOutcome_UnknownCopyWithImpl<$Res>
    implements $BridgeExtendOutcome_UnknownCopyWith<$Res> {
  _$BridgeExtendOutcome_UnknownCopyWithImpl(this._self, this._then);

  final BridgeExtendOutcome_Unknown _self;
  final $Res Function(BridgeExtendOutcome_Unknown) _then;

/// Create a copy of BridgeExtendOutcome
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? hours = null,Object? words = null,}) {
  return _then(BridgeExtendOutcome_Unknown(
hours: null == hours ? _self.hours : hours // ignore: cast_nullable_to_non_nullable
as int,words: null == words ? _self.words : words // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class BridgeExtendOutcome_Pending extends BridgeExtendOutcome {
  const BridgeExtendOutcome_Pending({required this.words}): super._();
  

 final  String words;

/// Create a copy of BridgeExtendOutcome
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeExtendOutcome_PendingCopyWith<BridgeExtendOutcome_Pending> get copyWith => _$BridgeExtendOutcome_PendingCopyWithImpl<BridgeExtendOutcome_Pending>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeExtendOutcome_Pending&&(identical(other.words, words) || other.words == words));
}


@override
int get hashCode => Object.hash(runtimeType,words);

@override
String toString() {
  return 'BridgeExtendOutcome.pending(words: $words)';
}


}

/// @nodoc
abstract mixin class $BridgeExtendOutcome_PendingCopyWith<$Res> implements $BridgeExtendOutcomeCopyWith<$Res> {
  factory $BridgeExtendOutcome_PendingCopyWith(BridgeExtendOutcome_Pending value, $Res Function(BridgeExtendOutcome_Pending) _then) = _$BridgeExtendOutcome_PendingCopyWithImpl;
@useResult
$Res call({
 String words
});




}
/// @nodoc
class _$BridgeExtendOutcome_PendingCopyWithImpl<$Res>
    implements $BridgeExtendOutcome_PendingCopyWith<$Res> {
  _$BridgeExtendOutcome_PendingCopyWithImpl(this._self, this._then);

  final BridgeExtendOutcome_Pending _self;
  final $Res Function(BridgeExtendOutcome_Pending) _then;

/// Create a copy of BridgeExtendOutcome
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? words = null,}) {
  return _then(BridgeExtendOutcome_Pending(
words: null == words ? _self.words : words // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on

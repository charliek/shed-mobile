// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'dto_lane.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$BridgeLaneAnswer {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeLaneAnswer);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'BridgeLaneAnswer()';
}


}

/// @nodoc
class $BridgeLaneAnswerCopyWith<$Res>  {
$BridgeLaneAnswerCopyWith(BridgeLaneAnswer _, $Res Function(BridgeLaneAnswer) __);
}


/// Adds pattern-matching-related methods to [BridgeLaneAnswer].
extension BridgeLaneAnswerPatterns on BridgeLaneAnswer {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeLaneAnswer_Permission value)?  permission,TResult Function( BridgeLaneAnswer_Choice value)?  choice,TResult Function( BridgeLaneAnswer_Question value)?  question,TResult Function( BridgeLaneAnswer_Reject value)?  reject,TResult Function( BridgeLaneAnswer_Raw value)?  raw,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeLaneAnswer_Permission() when permission != null:
return permission(_that);case BridgeLaneAnswer_Choice() when choice != null:
return choice(_that);case BridgeLaneAnswer_Question() when question != null:
return question(_that);case BridgeLaneAnswer_Reject() when reject != null:
return reject(_that);case BridgeLaneAnswer_Raw() when raw != null:
return raw(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeLaneAnswer_Permission value)  permission,required TResult Function( BridgeLaneAnswer_Choice value)  choice,required TResult Function( BridgeLaneAnswer_Question value)  question,required TResult Function( BridgeLaneAnswer_Reject value)  reject,required TResult Function( BridgeLaneAnswer_Raw value)  raw,}){
final _that = this;
switch (_that) {
case BridgeLaneAnswer_Permission():
return permission(_that);case BridgeLaneAnswer_Choice():
return choice(_that);case BridgeLaneAnswer_Question():
return question(_that);case BridgeLaneAnswer_Reject():
return reject(_that);case BridgeLaneAnswer_Raw():
return raw(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeLaneAnswer_Permission value)?  permission,TResult? Function( BridgeLaneAnswer_Choice value)?  choice,TResult? Function( BridgeLaneAnswer_Question value)?  question,TResult? Function( BridgeLaneAnswer_Reject value)?  reject,TResult? Function( BridgeLaneAnswer_Raw value)?  raw,}){
final _that = this;
switch (_that) {
case BridgeLaneAnswer_Permission() when permission != null:
return permission(_that);case BridgeLaneAnswer_Choice() when choice != null:
return choice(_that);case BridgeLaneAnswer_Question() when question != null:
return question(_that);case BridgeLaneAnswer_Reject() when reject != null:
return reject(_that);case BridgeLaneAnswer_Raw() when raw != null:
return raw(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( BridgeLaneDecision decision)?  permission,TResult Function( String optionId)?  choice,TResult Function( List<List<String>> answers,  List<String?> customText)?  question,TResult Function()?  reject,TResult Function( String json)?  raw,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeLaneAnswer_Permission() when permission != null:
return permission(_that.decision);case BridgeLaneAnswer_Choice() when choice != null:
return choice(_that.optionId);case BridgeLaneAnswer_Question() when question != null:
return question(_that.answers,_that.customText);case BridgeLaneAnswer_Reject() when reject != null:
return reject();case BridgeLaneAnswer_Raw() when raw != null:
return raw(_that.json);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( BridgeLaneDecision decision)  permission,required TResult Function( String optionId)  choice,required TResult Function( List<List<String>> answers,  List<String?> customText)  question,required TResult Function()  reject,required TResult Function( String json)  raw,}) {final _that = this;
switch (_that) {
case BridgeLaneAnswer_Permission():
return permission(_that.decision);case BridgeLaneAnswer_Choice():
return choice(_that.optionId);case BridgeLaneAnswer_Question():
return question(_that.answers,_that.customText);case BridgeLaneAnswer_Reject():
return reject();case BridgeLaneAnswer_Raw():
return raw(_that.json);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( BridgeLaneDecision decision)?  permission,TResult? Function( String optionId)?  choice,TResult? Function( List<List<String>> answers,  List<String?> customText)?  question,TResult? Function()?  reject,TResult? Function( String json)?  raw,}) {final _that = this;
switch (_that) {
case BridgeLaneAnswer_Permission() when permission != null:
return permission(_that.decision);case BridgeLaneAnswer_Choice() when choice != null:
return choice(_that.optionId);case BridgeLaneAnswer_Question() when question != null:
return question(_that.answers,_that.customText);case BridgeLaneAnswer_Reject() when reject != null:
return reject();case BridgeLaneAnswer_Raw() when raw != null:
return raw(_that.json);case _:
  return null;

}
}

}

/// @nodoc


class BridgeLaneAnswer_Permission extends BridgeLaneAnswer {
  const BridgeLaneAnswer_Permission({required this.decision}): super._();
  

 final  BridgeLaneDecision decision;

/// Create a copy of BridgeLaneAnswer
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeLaneAnswer_PermissionCopyWith<BridgeLaneAnswer_Permission> get copyWith => _$BridgeLaneAnswer_PermissionCopyWithImpl<BridgeLaneAnswer_Permission>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeLaneAnswer_Permission&&(identical(other.decision, decision) || other.decision == decision));
}


@override
int get hashCode => Object.hash(runtimeType,decision);

@override
String toString() {
  return 'BridgeLaneAnswer.permission(decision: $decision)';
}


}

/// @nodoc
abstract mixin class $BridgeLaneAnswer_PermissionCopyWith<$Res> implements $BridgeLaneAnswerCopyWith<$Res> {
  factory $BridgeLaneAnswer_PermissionCopyWith(BridgeLaneAnswer_Permission value, $Res Function(BridgeLaneAnswer_Permission) _then) = _$BridgeLaneAnswer_PermissionCopyWithImpl;
@useResult
$Res call({
 BridgeLaneDecision decision
});




}
/// @nodoc
class _$BridgeLaneAnswer_PermissionCopyWithImpl<$Res>
    implements $BridgeLaneAnswer_PermissionCopyWith<$Res> {
  _$BridgeLaneAnswer_PermissionCopyWithImpl(this._self, this._then);

  final BridgeLaneAnswer_Permission _self;
  final $Res Function(BridgeLaneAnswer_Permission) _then;

/// Create a copy of BridgeLaneAnswer
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? decision = null,}) {
  return _then(BridgeLaneAnswer_Permission(
decision: null == decision ? _self.decision : decision // ignore: cast_nullable_to_non_nullable
as BridgeLaneDecision,
  ));
}


}

/// @nodoc


class BridgeLaneAnswer_Choice extends BridgeLaneAnswer {
  const BridgeLaneAnswer_Choice({required this.optionId}): super._();
  

 final  String optionId;

/// Create a copy of BridgeLaneAnswer
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeLaneAnswer_ChoiceCopyWith<BridgeLaneAnswer_Choice> get copyWith => _$BridgeLaneAnswer_ChoiceCopyWithImpl<BridgeLaneAnswer_Choice>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeLaneAnswer_Choice&&(identical(other.optionId, optionId) || other.optionId == optionId));
}


@override
int get hashCode => Object.hash(runtimeType,optionId);

@override
String toString() {
  return 'BridgeLaneAnswer.choice(optionId: $optionId)';
}


}

/// @nodoc
abstract mixin class $BridgeLaneAnswer_ChoiceCopyWith<$Res> implements $BridgeLaneAnswerCopyWith<$Res> {
  factory $BridgeLaneAnswer_ChoiceCopyWith(BridgeLaneAnswer_Choice value, $Res Function(BridgeLaneAnswer_Choice) _then) = _$BridgeLaneAnswer_ChoiceCopyWithImpl;
@useResult
$Res call({
 String optionId
});




}
/// @nodoc
class _$BridgeLaneAnswer_ChoiceCopyWithImpl<$Res>
    implements $BridgeLaneAnswer_ChoiceCopyWith<$Res> {
  _$BridgeLaneAnswer_ChoiceCopyWithImpl(this._self, this._then);

  final BridgeLaneAnswer_Choice _self;
  final $Res Function(BridgeLaneAnswer_Choice) _then;

/// Create a copy of BridgeLaneAnswer
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? optionId = null,}) {
  return _then(BridgeLaneAnswer_Choice(
optionId: null == optionId ? _self.optionId : optionId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class BridgeLaneAnswer_Question extends BridgeLaneAnswer {
  const BridgeLaneAnswer_Question({required final  List<List<String>> answers, required final  List<String?> customText}): _answers = answers,_customText = customText,super._();
  

 final  List<List<String>> _answers;
 List<List<String>> get answers {
  if (_answers is EqualUnmodifiableListView) return _answers;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_answers);
}

/// Free text per question, positional like `answers`; `None` where the
/// human typed nothing. Empty list = no free text anywhere.
///
/// A `Vec<Option<String>>` — `List<String?>` in Dart — is the one
/// genuinely awkward shape in this mirror, and it is load-bearing: a
/// `None` and a `Some("")` are different answers, and flattening the
/// hole would lose which question the text was for. The adapter refuses
/// text aimed at a question whose `custom` is false, so a panel that
/// gates its text field on [`BridgeLaneQuestion::custom`] never sends
/// one that will be refused.
 final  List<String?> _customText;
/// Free text per question, positional like `answers`; `None` where the
/// human typed nothing. Empty list = no free text anywhere.
///
/// A `Vec<Option<String>>` — `List<String?>` in Dart — is the one
/// genuinely awkward shape in this mirror, and it is load-bearing: a
/// `None` and a `Some("")` are different answers, and flattening the
/// hole would lose which question the text was for. The adapter refuses
/// text aimed at a question whose `custom` is false, so a panel that
/// gates its text field on [`BridgeLaneQuestion::custom`] never sends
/// one that will be refused.
 List<String?> get customText {
  if (_customText is EqualUnmodifiableListView) return _customText;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_customText);
}


/// Create a copy of BridgeLaneAnswer
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeLaneAnswer_QuestionCopyWith<BridgeLaneAnswer_Question> get copyWith => _$BridgeLaneAnswer_QuestionCopyWithImpl<BridgeLaneAnswer_Question>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeLaneAnswer_Question&&const DeepCollectionEquality().equals(other._answers, _answers)&&const DeepCollectionEquality().equals(other._customText, _customText));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(_answers),const DeepCollectionEquality().hash(_customText));

@override
String toString() {
  return 'BridgeLaneAnswer.question(answers: $answers, customText: $customText)';
}


}

/// @nodoc
abstract mixin class $BridgeLaneAnswer_QuestionCopyWith<$Res> implements $BridgeLaneAnswerCopyWith<$Res> {
  factory $BridgeLaneAnswer_QuestionCopyWith(BridgeLaneAnswer_Question value, $Res Function(BridgeLaneAnswer_Question) _then) = _$BridgeLaneAnswer_QuestionCopyWithImpl;
@useResult
$Res call({
 List<List<String>> answers, List<String?> customText
});




}
/// @nodoc
class _$BridgeLaneAnswer_QuestionCopyWithImpl<$Res>
    implements $BridgeLaneAnswer_QuestionCopyWith<$Res> {
  _$BridgeLaneAnswer_QuestionCopyWithImpl(this._self, this._then);

  final BridgeLaneAnswer_Question _self;
  final $Res Function(BridgeLaneAnswer_Question) _then;

/// Create a copy of BridgeLaneAnswer
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? answers = null,Object? customText = null,}) {
  return _then(BridgeLaneAnswer_Question(
answers: null == answers ? _self._answers : answers // ignore: cast_nullable_to_non_nullable
as List<List<String>>,customText: null == customText ? _self._customText : customText // ignore: cast_nullable_to_non_nullable
as List<String?>,
  ));
}


}

/// @nodoc


class BridgeLaneAnswer_Reject extends BridgeLaneAnswer {
  const BridgeLaneAnswer_Reject(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeLaneAnswer_Reject);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'BridgeLaneAnswer.reject()';
}


}




/// @nodoc


class BridgeLaneAnswer_Raw extends BridgeLaneAnswer {
  const BridgeLaneAnswer_Raw({required this.json}): super._();
  

 final  String json;

/// Create a copy of BridgeLaneAnswer
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeLaneAnswer_RawCopyWith<BridgeLaneAnswer_Raw> get copyWith => _$BridgeLaneAnswer_RawCopyWithImpl<BridgeLaneAnswer_Raw>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeLaneAnswer_Raw&&(identical(other.json, json) || other.json == json));
}


@override
int get hashCode => Object.hash(runtimeType,json);

@override
String toString() {
  return 'BridgeLaneAnswer.raw(json: $json)';
}


}

/// @nodoc
abstract mixin class $BridgeLaneAnswer_RawCopyWith<$Res> implements $BridgeLaneAnswerCopyWith<$Res> {
  factory $BridgeLaneAnswer_RawCopyWith(BridgeLaneAnswer_Raw value, $Res Function(BridgeLaneAnswer_Raw) _then) = _$BridgeLaneAnswer_RawCopyWithImpl;
@useResult
$Res call({
 String json
});




}
/// @nodoc
class _$BridgeLaneAnswer_RawCopyWithImpl<$Res>
    implements $BridgeLaneAnswer_RawCopyWith<$Res> {
  _$BridgeLaneAnswer_RawCopyWithImpl(this._self, this._then);

  final BridgeLaneAnswer_Raw _self;
  final $Res Function(BridgeLaneAnswer_Raw) _then;

/// Create a copy of BridgeLaneAnswer
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? json = null,}) {
  return _then(BridgeLaneAnswer_Raw(
json: null == json ? _self.json : json // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$BridgeLaneApprovalKind {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeLaneApprovalKind);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'BridgeLaneApprovalKind()';
}


}

/// @nodoc
class $BridgeLaneApprovalKindCopyWith<$Res>  {
$BridgeLaneApprovalKindCopyWith(BridgeLaneApprovalKind _, $Res Function(BridgeLaneApprovalKind) __);
}


/// Adds pattern-matching-related methods to [BridgeLaneApprovalKind].
extension BridgeLaneApprovalKindPatterns on BridgeLaneApprovalKind {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeLaneApprovalKind_Permission value)?  permission,TResult Function( BridgeLaneApprovalKind_Question value)?  question,TResult Function( BridgeLaneApprovalKind_PlanApproval value)?  planApproval,TResult Function( BridgeLaneApprovalKind_McpElicitation value)?  mcpElicitation,TResult Function( BridgeLaneApprovalKind_Other value)?  other,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeLaneApprovalKind_Permission() when permission != null:
return permission(_that);case BridgeLaneApprovalKind_Question() when question != null:
return question(_that);case BridgeLaneApprovalKind_PlanApproval() when planApproval != null:
return planApproval(_that);case BridgeLaneApprovalKind_McpElicitation() when mcpElicitation != null:
return mcpElicitation(_that);case BridgeLaneApprovalKind_Other() when other != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeLaneApprovalKind_Permission value)  permission,required TResult Function( BridgeLaneApprovalKind_Question value)  question,required TResult Function( BridgeLaneApprovalKind_PlanApproval value)  planApproval,required TResult Function( BridgeLaneApprovalKind_McpElicitation value)  mcpElicitation,required TResult Function( BridgeLaneApprovalKind_Other value)  other,}){
final _that = this;
switch (_that) {
case BridgeLaneApprovalKind_Permission():
return permission(_that);case BridgeLaneApprovalKind_Question():
return question(_that);case BridgeLaneApprovalKind_PlanApproval():
return planApproval(_that);case BridgeLaneApprovalKind_McpElicitation():
return mcpElicitation(_that);case BridgeLaneApprovalKind_Other():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeLaneApprovalKind_Permission value)?  permission,TResult? Function( BridgeLaneApprovalKind_Question value)?  question,TResult? Function( BridgeLaneApprovalKind_PlanApproval value)?  planApproval,TResult? Function( BridgeLaneApprovalKind_McpElicitation value)?  mcpElicitation,TResult? Function( BridgeLaneApprovalKind_Other value)?  other,}){
final _that = this;
switch (_that) {
case BridgeLaneApprovalKind_Permission() when permission != null:
return permission(_that);case BridgeLaneApprovalKind_Question() when question != null:
return question(_that);case BridgeLaneApprovalKind_PlanApproval() when planApproval != null:
return planApproval(_that);case BridgeLaneApprovalKind_McpElicitation() when mcpElicitation != null:
return mcpElicitation(_that);case BridgeLaneApprovalKind_Other() when other != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  permission,TResult Function()?  question,TResult Function()?  planApproval,TResult Function()?  mcpElicitation,TResult Function( String raw)?  other,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeLaneApprovalKind_Permission() when permission != null:
return permission();case BridgeLaneApprovalKind_Question() when question != null:
return question();case BridgeLaneApprovalKind_PlanApproval() when planApproval != null:
return planApproval();case BridgeLaneApprovalKind_McpElicitation() when mcpElicitation != null:
return mcpElicitation();case BridgeLaneApprovalKind_Other() when other != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  permission,required TResult Function()  question,required TResult Function()  planApproval,required TResult Function()  mcpElicitation,required TResult Function( String raw)  other,}) {final _that = this;
switch (_that) {
case BridgeLaneApprovalKind_Permission():
return permission();case BridgeLaneApprovalKind_Question():
return question();case BridgeLaneApprovalKind_PlanApproval():
return planApproval();case BridgeLaneApprovalKind_McpElicitation():
return mcpElicitation();case BridgeLaneApprovalKind_Other():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  permission,TResult? Function()?  question,TResult? Function()?  planApproval,TResult? Function()?  mcpElicitation,TResult? Function( String raw)?  other,}) {final _that = this;
switch (_that) {
case BridgeLaneApprovalKind_Permission() when permission != null:
return permission();case BridgeLaneApprovalKind_Question() when question != null:
return question();case BridgeLaneApprovalKind_PlanApproval() when planApproval != null:
return planApproval();case BridgeLaneApprovalKind_McpElicitation() when mcpElicitation != null:
return mcpElicitation();case BridgeLaneApprovalKind_Other() when other != null:
return other(_that.raw);case _:
  return null;

}
}

}

/// @nodoc


class BridgeLaneApprovalKind_Permission extends BridgeLaneApprovalKind {
  const BridgeLaneApprovalKind_Permission(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeLaneApprovalKind_Permission);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'BridgeLaneApprovalKind.permission()';
}


}




/// @nodoc


class BridgeLaneApprovalKind_Question extends BridgeLaneApprovalKind {
  const BridgeLaneApprovalKind_Question(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeLaneApprovalKind_Question);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'BridgeLaneApprovalKind.question()';
}


}




/// @nodoc


class BridgeLaneApprovalKind_PlanApproval extends BridgeLaneApprovalKind {
  const BridgeLaneApprovalKind_PlanApproval(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeLaneApprovalKind_PlanApproval);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'BridgeLaneApprovalKind.planApproval()';
}


}




/// @nodoc


class BridgeLaneApprovalKind_McpElicitation extends BridgeLaneApprovalKind {
  const BridgeLaneApprovalKind_McpElicitation(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeLaneApprovalKind_McpElicitation);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'BridgeLaneApprovalKind.mcpElicitation()';
}


}




/// @nodoc


class BridgeLaneApprovalKind_Other extends BridgeLaneApprovalKind {
  const BridgeLaneApprovalKind_Other({required this.raw}): super._();
  

 final  String raw;

/// Create a copy of BridgeLaneApprovalKind
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeLaneApprovalKind_OtherCopyWith<BridgeLaneApprovalKind_Other> get copyWith => _$BridgeLaneApprovalKind_OtherCopyWithImpl<BridgeLaneApprovalKind_Other>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeLaneApprovalKind_Other&&(identical(other.raw, raw) || other.raw == raw));
}


@override
int get hashCode => Object.hash(runtimeType,raw);

@override
String toString() {
  return 'BridgeLaneApprovalKind.other(raw: $raw)';
}


}

/// @nodoc
abstract mixin class $BridgeLaneApprovalKind_OtherCopyWith<$Res> implements $BridgeLaneApprovalKindCopyWith<$Res> {
  factory $BridgeLaneApprovalKind_OtherCopyWith(BridgeLaneApprovalKind_Other value, $Res Function(BridgeLaneApprovalKind_Other) _then) = _$BridgeLaneApprovalKind_OtherCopyWithImpl;
@useResult
$Res call({
 String raw
});




}
/// @nodoc
class _$BridgeLaneApprovalKind_OtherCopyWithImpl<$Res>
    implements $BridgeLaneApprovalKind_OtherCopyWith<$Res> {
  _$BridgeLaneApprovalKind_OtherCopyWithImpl(this._self, this._then);

  final BridgeLaneApprovalKind_Other _self;
  final $Res Function(BridgeLaneApprovalKind_Other) _then;

/// Create a copy of BridgeLaneApprovalKind
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? raw = null,}) {
  return _then(BridgeLaneApprovalKind_Other(
raw: null == raw ? _self.raw : raw // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$BridgeLaneApprovalStatus {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeLaneApprovalStatus);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'BridgeLaneApprovalStatus()';
}


}

/// @nodoc
class $BridgeLaneApprovalStatusCopyWith<$Res>  {
$BridgeLaneApprovalStatusCopyWith(BridgeLaneApprovalStatus _, $Res Function(BridgeLaneApprovalStatus) __);
}


/// Adds pattern-matching-related methods to [BridgeLaneApprovalStatus].
extension BridgeLaneApprovalStatusPatterns on BridgeLaneApprovalStatus {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeLaneApprovalStatus_Pending value)?  pending,TResult Function( BridgeLaneApprovalStatus_Submitted value)?  submitted,TResult Function( BridgeLaneApprovalStatus_Resolved value)?  resolved,TResult Function( BridgeLaneApprovalStatus_Other value)?  other,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeLaneApprovalStatus_Pending() when pending != null:
return pending(_that);case BridgeLaneApprovalStatus_Submitted() when submitted != null:
return submitted(_that);case BridgeLaneApprovalStatus_Resolved() when resolved != null:
return resolved(_that);case BridgeLaneApprovalStatus_Other() when other != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeLaneApprovalStatus_Pending value)  pending,required TResult Function( BridgeLaneApprovalStatus_Submitted value)  submitted,required TResult Function( BridgeLaneApprovalStatus_Resolved value)  resolved,required TResult Function( BridgeLaneApprovalStatus_Other value)  other,}){
final _that = this;
switch (_that) {
case BridgeLaneApprovalStatus_Pending():
return pending(_that);case BridgeLaneApprovalStatus_Submitted():
return submitted(_that);case BridgeLaneApprovalStatus_Resolved():
return resolved(_that);case BridgeLaneApprovalStatus_Other():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeLaneApprovalStatus_Pending value)?  pending,TResult? Function( BridgeLaneApprovalStatus_Submitted value)?  submitted,TResult? Function( BridgeLaneApprovalStatus_Resolved value)?  resolved,TResult? Function( BridgeLaneApprovalStatus_Other value)?  other,}){
final _that = this;
switch (_that) {
case BridgeLaneApprovalStatus_Pending() when pending != null:
return pending(_that);case BridgeLaneApprovalStatus_Submitted() when submitted != null:
return submitted(_that);case BridgeLaneApprovalStatus_Resolved() when resolved != null:
return resolved(_that);case BridgeLaneApprovalStatus_Other() when other != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  pending,TResult Function()?  submitted,TResult Function()?  resolved,TResult Function( String raw)?  other,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeLaneApprovalStatus_Pending() when pending != null:
return pending();case BridgeLaneApprovalStatus_Submitted() when submitted != null:
return submitted();case BridgeLaneApprovalStatus_Resolved() when resolved != null:
return resolved();case BridgeLaneApprovalStatus_Other() when other != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  pending,required TResult Function()  submitted,required TResult Function()  resolved,required TResult Function( String raw)  other,}) {final _that = this;
switch (_that) {
case BridgeLaneApprovalStatus_Pending():
return pending();case BridgeLaneApprovalStatus_Submitted():
return submitted();case BridgeLaneApprovalStatus_Resolved():
return resolved();case BridgeLaneApprovalStatus_Other():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  pending,TResult? Function()?  submitted,TResult? Function()?  resolved,TResult? Function( String raw)?  other,}) {final _that = this;
switch (_that) {
case BridgeLaneApprovalStatus_Pending() when pending != null:
return pending();case BridgeLaneApprovalStatus_Submitted() when submitted != null:
return submitted();case BridgeLaneApprovalStatus_Resolved() when resolved != null:
return resolved();case BridgeLaneApprovalStatus_Other() when other != null:
return other(_that.raw);case _:
  return null;

}
}

}

/// @nodoc


class BridgeLaneApprovalStatus_Pending extends BridgeLaneApprovalStatus {
  const BridgeLaneApprovalStatus_Pending(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeLaneApprovalStatus_Pending);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'BridgeLaneApprovalStatus.pending()';
}


}




/// @nodoc


class BridgeLaneApprovalStatus_Submitted extends BridgeLaneApprovalStatus {
  const BridgeLaneApprovalStatus_Submitted(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeLaneApprovalStatus_Submitted);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'BridgeLaneApprovalStatus.submitted()';
}


}




/// @nodoc


class BridgeLaneApprovalStatus_Resolved extends BridgeLaneApprovalStatus {
  const BridgeLaneApprovalStatus_Resolved(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeLaneApprovalStatus_Resolved);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'BridgeLaneApprovalStatus.resolved()';
}


}




/// @nodoc


class BridgeLaneApprovalStatus_Other extends BridgeLaneApprovalStatus {
  const BridgeLaneApprovalStatus_Other({required this.raw}): super._();
  

 final  String raw;

/// Create a copy of BridgeLaneApprovalStatus
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeLaneApprovalStatus_OtherCopyWith<BridgeLaneApprovalStatus_Other> get copyWith => _$BridgeLaneApprovalStatus_OtherCopyWithImpl<BridgeLaneApprovalStatus_Other>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeLaneApprovalStatus_Other&&(identical(other.raw, raw) || other.raw == raw));
}


@override
int get hashCode => Object.hash(runtimeType,raw);

@override
String toString() {
  return 'BridgeLaneApprovalStatus.other(raw: $raw)';
}


}

/// @nodoc
abstract mixin class $BridgeLaneApprovalStatus_OtherCopyWith<$Res> implements $BridgeLaneApprovalStatusCopyWith<$Res> {
  factory $BridgeLaneApprovalStatus_OtherCopyWith(BridgeLaneApprovalStatus_Other value, $Res Function(BridgeLaneApprovalStatus_Other) _then) = _$BridgeLaneApprovalStatus_OtherCopyWithImpl;
@useResult
$Res call({
 String raw
});




}
/// @nodoc
class _$BridgeLaneApprovalStatus_OtherCopyWithImpl<$Res>
    implements $BridgeLaneApprovalStatus_OtherCopyWith<$Res> {
  _$BridgeLaneApprovalStatus_OtherCopyWithImpl(this._self, this._then);

  final BridgeLaneApprovalStatus_Other _self;
  final $Res Function(BridgeLaneApprovalStatus_Other) _then;

/// Create a copy of BridgeLaneApprovalStatus
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? raw = null,}) {
  return _then(BridgeLaneApprovalStatus_Other(
raw: null == raw ? _self.raw : raw // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$BridgeLaneError {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeLaneError);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'BridgeLaneError()';
}


}

/// @nodoc
class $BridgeLaneErrorCopyWith<$Res>  {
$BridgeLaneErrorCopyWith(BridgeLaneError _, $Res Function(BridgeLaneError) __);
}


/// Adds pattern-matching-related methods to [BridgeLaneError].
extension BridgeLaneErrorPatterns on BridgeLaneError {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeLaneError_Unauthorized value)?  unauthorized,TResult Function( BridgeLaneError_BadRequest value)?  badRequest,TResult Function( BridgeLaneError_UnknownSession value)?  unknownSession,TResult Function( BridgeLaneError_UnknownApproval value)?  unknownApproval,TResult Function( BridgeLaneError_AlreadySubmitted value)?  alreadySubmitted,TResult Function( BridgeLaneError_AlreadyResolved value)?  alreadyResolved,TResult Function( BridgeLaneError_NotAccepting value)?  notAccepting,TResult Function( BridgeLaneError_Unavailable value)?  unavailable,TResult Function( BridgeLaneError_Failed value)?  failed,TResult Function( BridgeLaneError_NoLane value)?  noLane,TResult Function( BridgeLaneError_UnsupportedLane value)?  unsupportedLane,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeLaneError_Unauthorized() when unauthorized != null:
return unauthorized(_that);case BridgeLaneError_BadRequest() when badRequest != null:
return badRequest(_that);case BridgeLaneError_UnknownSession() when unknownSession != null:
return unknownSession(_that);case BridgeLaneError_UnknownApproval() when unknownApproval != null:
return unknownApproval(_that);case BridgeLaneError_AlreadySubmitted() when alreadySubmitted != null:
return alreadySubmitted(_that);case BridgeLaneError_AlreadyResolved() when alreadyResolved != null:
return alreadyResolved(_that);case BridgeLaneError_NotAccepting() when notAccepting != null:
return notAccepting(_that);case BridgeLaneError_Unavailable() when unavailable != null:
return unavailable(_that);case BridgeLaneError_Failed() when failed != null:
return failed(_that);case BridgeLaneError_NoLane() when noLane != null:
return noLane(_that);case BridgeLaneError_UnsupportedLane() when unsupportedLane != null:
return unsupportedLane(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeLaneError_Unauthorized value)  unauthorized,required TResult Function( BridgeLaneError_BadRequest value)  badRequest,required TResult Function( BridgeLaneError_UnknownSession value)  unknownSession,required TResult Function( BridgeLaneError_UnknownApproval value)  unknownApproval,required TResult Function( BridgeLaneError_AlreadySubmitted value)  alreadySubmitted,required TResult Function( BridgeLaneError_AlreadyResolved value)  alreadyResolved,required TResult Function( BridgeLaneError_NotAccepting value)  notAccepting,required TResult Function( BridgeLaneError_Unavailable value)  unavailable,required TResult Function( BridgeLaneError_Failed value)  failed,required TResult Function( BridgeLaneError_NoLane value)  noLane,required TResult Function( BridgeLaneError_UnsupportedLane value)  unsupportedLane,}){
final _that = this;
switch (_that) {
case BridgeLaneError_Unauthorized():
return unauthorized(_that);case BridgeLaneError_BadRequest():
return badRequest(_that);case BridgeLaneError_UnknownSession():
return unknownSession(_that);case BridgeLaneError_UnknownApproval():
return unknownApproval(_that);case BridgeLaneError_AlreadySubmitted():
return alreadySubmitted(_that);case BridgeLaneError_AlreadyResolved():
return alreadyResolved(_that);case BridgeLaneError_NotAccepting():
return notAccepting(_that);case BridgeLaneError_Unavailable():
return unavailable(_that);case BridgeLaneError_Failed():
return failed(_that);case BridgeLaneError_NoLane():
return noLane(_that);case BridgeLaneError_UnsupportedLane():
return unsupportedLane(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeLaneError_Unauthorized value)?  unauthorized,TResult? Function( BridgeLaneError_BadRequest value)?  badRequest,TResult? Function( BridgeLaneError_UnknownSession value)?  unknownSession,TResult? Function( BridgeLaneError_UnknownApproval value)?  unknownApproval,TResult? Function( BridgeLaneError_AlreadySubmitted value)?  alreadySubmitted,TResult? Function( BridgeLaneError_AlreadyResolved value)?  alreadyResolved,TResult? Function( BridgeLaneError_NotAccepting value)?  notAccepting,TResult? Function( BridgeLaneError_Unavailable value)?  unavailable,TResult? Function( BridgeLaneError_Failed value)?  failed,TResult? Function( BridgeLaneError_NoLane value)?  noLane,TResult? Function( BridgeLaneError_UnsupportedLane value)?  unsupportedLane,}){
final _that = this;
switch (_that) {
case BridgeLaneError_Unauthorized() when unauthorized != null:
return unauthorized(_that);case BridgeLaneError_BadRequest() when badRequest != null:
return badRequest(_that);case BridgeLaneError_UnknownSession() when unknownSession != null:
return unknownSession(_that);case BridgeLaneError_UnknownApproval() when unknownApproval != null:
return unknownApproval(_that);case BridgeLaneError_AlreadySubmitted() when alreadySubmitted != null:
return alreadySubmitted(_that);case BridgeLaneError_AlreadyResolved() when alreadyResolved != null:
return alreadyResolved(_that);case BridgeLaneError_NotAccepting() when notAccepting != null:
return notAccepting(_that);case BridgeLaneError_Unavailable() when unavailable != null:
return unavailable(_that);case BridgeLaneError_Failed() when failed != null:
return failed(_that);case BridgeLaneError_NoLane() when noLane != null:
return noLane(_that);case BridgeLaneError_UnsupportedLane() when unsupportedLane != null:
return unsupportedLane(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  unauthorized,TResult Function( String msg)?  badRequest,TResult Function()?  unknownSession,TResult Function()?  unknownApproval,TResult Function()?  alreadySubmitted,TResult Function()?  alreadyResolved,TResult Function()?  notAccepting,TResult Function( String msg)?  unavailable,TResult Function( String msg)?  failed,TResult Function( String msg)?  noLane,TResult Function( String kind)?  unsupportedLane,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeLaneError_Unauthorized() when unauthorized != null:
return unauthorized();case BridgeLaneError_BadRequest() when badRequest != null:
return badRequest(_that.msg);case BridgeLaneError_UnknownSession() when unknownSession != null:
return unknownSession();case BridgeLaneError_UnknownApproval() when unknownApproval != null:
return unknownApproval();case BridgeLaneError_AlreadySubmitted() when alreadySubmitted != null:
return alreadySubmitted();case BridgeLaneError_AlreadyResolved() when alreadyResolved != null:
return alreadyResolved();case BridgeLaneError_NotAccepting() when notAccepting != null:
return notAccepting();case BridgeLaneError_Unavailable() when unavailable != null:
return unavailable(_that.msg);case BridgeLaneError_Failed() when failed != null:
return failed(_that.msg);case BridgeLaneError_NoLane() when noLane != null:
return noLane(_that.msg);case BridgeLaneError_UnsupportedLane() when unsupportedLane != null:
return unsupportedLane(_that.kind);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  unauthorized,required TResult Function( String msg)  badRequest,required TResult Function()  unknownSession,required TResult Function()  unknownApproval,required TResult Function()  alreadySubmitted,required TResult Function()  alreadyResolved,required TResult Function()  notAccepting,required TResult Function( String msg)  unavailable,required TResult Function( String msg)  failed,required TResult Function( String msg)  noLane,required TResult Function( String kind)  unsupportedLane,}) {final _that = this;
switch (_that) {
case BridgeLaneError_Unauthorized():
return unauthorized();case BridgeLaneError_BadRequest():
return badRequest(_that.msg);case BridgeLaneError_UnknownSession():
return unknownSession();case BridgeLaneError_UnknownApproval():
return unknownApproval();case BridgeLaneError_AlreadySubmitted():
return alreadySubmitted();case BridgeLaneError_AlreadyResolved():
return alreadyResolved();case BridgeLaneError_NotAccepting():
return notAccepting();case BridgeLaneError_Unavailable():
return unavailable(_that.msg);case BridgeLaneError_Failed():
return failed(_that.msg);case BridgeLaneError_NoLane():
return noLane(_that.msg);case BridgeLaneError_UnsupportedLane():
return unsupportedLane(_that.kind);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  unauthorized,TResult? Function( String msg)?  badRequest,TResult? Function()?  unknownSession,TResult? Function()?  unknownApproval,TResult? Function()?  alreadySubmitted,TResult? Function()?  alreadyResolved,TResult? Function()?  notAccepting,TResult? Function( String msg)?  unavailable,TResult? Function( String msg)?  failed,TResult? Function( String msg)?  noLane,TResult? Function( String kind)?  unsupportedLane,}) {final _that = this;
switch (_that) {
case BridgeLaneError_Unauthorized() when unauthorized != null:
return unauthorized();case BridgeLaneError_BadRequest() when badRequest != null:
return badRequest(_that.msg);case BridgeLaneError_UnknownSession() when unknownSession != null:
return unknownSession();case BridgeLaneError_UnknownApproval() when unknownApproval != null:
return unknownApproval();case BridgeLaneError_AlreadySubmitted() when alreadySubmitted != null:
return alreadySubmitted();case BridgeLaneError_AlreadyResolved() when alreadyResolved != null:
return alreadyResolved();case BridgeLaneError_NotAccepting() when notAccepting != null:
return notAccepting();case BridgeLaneError_Unavailable() when unavailable != null:
return unavailable(_that.msg);case BridgeLaneError_Failed() when failed != null:
return failed(_that.msg);case BridgeLaneError_NoLane() when noLane != null:
return noLane(_that.msg);case BridgeLaneError_UnsupportedLane() when unsupportedLane != null:
return unsupportedLane(_that.kind);case _:
  return null;

}
}

}

/// @nodoc


class BridgeLaneError_Unauthorized extends BridgeLaneError {
  const BridgeLaneError_Unauthorized(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeLaneError_Unauthorized);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'BridgeLaneError.unauthorized()';
}


}




/// @nodoc


class BridgeLaneError_BadRequest extends BridgeLaneError {
  const BridgeLaneError_BadRequest({required this.msg}): super._();
  

 final  String msg;

/// Create a copy of BridgeLaneError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeLaneError_BadRequestCopyWith<BridgeLaneError_BadRequest> get copyWith => _$BridgeLaneError_BadRequestCopyWithImpl<BridgeLaneError_BadRequest>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeLaneError_BadRequest&&(identical(other.msg, msg) || other.msg == msg));
}


@override
int get hashCode => Object.hash(runtimeType,msg);

@override
String toString() {
  return 'BridgeLaneError.badRequest(msg: $msg)';
}


}

/// @nodoc
abstract mixin class $BridgeLaneError_BadRequestCopyWith<$Res> implements $BridgeLaneErrorCopyWith<$Res> {
  factory $BridgeLaneError_BadRequestCopyWith(BridgeLaneError_BadRequest value, $Res Function(BridgeLaneError_BadRequest) _then) = _$BridgeLaneError_BadRequestCopyWithImpl;
@useResult
$Res call({
 String msg
});




}
/// @nodoc
class _$BridgeLaneError_BadRequestCopyWithImpl<$Res>
    implements $BridgeLaneError_BadRequestCopyWith<$Res> {
  _$BridgeLaneError_BadRequestCopyWithImpl(this._self, this._then);

  final BridgeLaneError_BadRequest _self;
  final $Res Function(BridgeLaneError_BadRequest) _then;

/// Create a copy of BridgeLaneError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? msg = null,}) {
  return _then(BridgeLaneError_BadRequest(
msg: null == msg ? _self.msg : msg // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class BridgeLaneError_UnknownSession extends BridgeLaneError {
  const BridgeLaneError_UnknownSession(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeLaneError_UnknownSession);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'BridgeLaneError.unknownSession()';
}


}




/// @nodoc


class BridgeLaneError_UnknownApproval extends BridgeLaneError {
  const BridgeLaneError_UnknownApproval(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeLaneError_UnknownApproval);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'BridgeLaneError.unknownApproval()';
}


}




/// @nodoc


class BridgeLaneError_AlreadySubmitted extends BridgeLaneError {
  const BridgeLaneError_AlreadySubmitted(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeLaneError_AlreadySubmitted);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'BridgeLaneError.alreadySubmitted()';
}


}




/// @nodoc


class BridgeLaneError_AlreadyResolved extends BridgeLaneError {
  const BridgeLaneError_AlreadyResolved(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeLaneError_AlreadyResolved);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'BridgeLaneError.alreadyResolved()';
}


}




/// @nodoc


class BridgeLaneError_NotAccepting extends BridgeLaneError {
  const BridgeLaneError_NotAccepting(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeLaneError_NotAccepting);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'BridgeLaneError.notAccepting()';
}


}




/// @nodoc


class BridgeLaneError_Unavailable extends BridgeLaneError {
  const BridgeLaneError_Unavailable({required this.msg}): super._();
  

 final  String msg;

/// Create a copy of BridgeLaneError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeLaneError_UnavailableCopyWith<BridgeLaneError_Unavailable> get copyWith => _$BridgeLaneError_UnavailableCopyWithImpl<BridgeLaneError_Unavailable>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeLaneError_Unavailable&&(identical(other.msg, msg) || other.msg == msg));
}


@override
int get hashCode => Object.hash(runtimeType,msg);

@override
String toString() {
  return 'BridgeLaneError.unavailable(msg: $msg)';
}


}

/// @nodoc
abstract mixin class $BridgeLaneError_UnavailableCopyWith<$Res> implements $BridgeLaneErrorCopyWith<$Res> {
  factory $BridgeLaneError_UnavailableCopyWith(BridgeLaneError_Unavailable value, $Res Function(BridgeLaneError_Unavailable) _then) = _$BridgeLaneError_UnavailableCopyWithImpl;
@useResult
$Res call({
 String msg
});




}
/// @nodoc
class _$BridgeLaneError_UnavailableCopyWithImpl<$Res>
    implements $BridgeLaneError_UnavailableCopyWith<$Res> {
  _$BridgeLaneError_UnavailableCopyWithImpl(this._self, this._then);

  final BridgeLaneError_Unavailable _self;
  final $Res Function(BridgeLaneError_Unavailable) _then;

/// Create a copy of BridgeLaneError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? msg = null,}) {
  return _then(BridgeLaneError_Unavailable(
msg: null == msg ? _self.msg : msg // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class BridgeLaneError_Failed extends BridgeLaneError {
  const BridgeLaneError_Failed({required this.msg}): super._();
  

 final  String msg;

/// Create a copy of BridgeLaneError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeLaneError_FailedCopyWith<BridgeLaneError_Failed> get copyWith => _$BridgeLaneError_FailedCopyWithImpl<BridgeLaneError_Failed>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeLaneError_Failed&&(identical(other.msg, msg) || other.msg == msg));
}


@override
int get hashCode => Object.hash(runtimeType,msg);

@override
String toString() {
  return 'BridgeLaneError.failed(msg: $msg)';
}


}

/// @nodoc
abstract mixin class $BridgeLaneError_FailedCopyWith<$Res> implements $BridgeLaneErrorCopyWith<$Res> {
  factory $BridgeLaneError_FailedCopyWith(BridgeLaneError_Failed value, $Res Function(BridgeLaneError_Failed) _then) = _$BridgeLaneError_FailedCopyWithImpl;
@useResult
$Res call({
 String msg
});




}
/// @nodoc
class _$BridgeLaneError_FailedCopyWithImpl<$Res>
    implements $BridgeLaneError_FailedCopyWith<$Res> {
  _$BridgeLaneError_FailedCopyWithImpl(this._self, this._then);

  final BridgeLaneError_Failed _self;
  final $Res Function(BridgeLaneError_Failed) _then;

/// Create a copy of BridgeLaneError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? msg = null,}) {
  return _then(BridgeLaneError_Failed(
msg: null == msg ? _self.msg : msg // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class BridgeLaneError_NoLane extends BridgeLaneError {
  const BridgeLaneError_NoLane({required this.msg}): super._();
  

 final  String msg;

/// Create a copy of BridgeLaneError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeLaneError_NoLaneCopyWith<BridgeLaneError_NoLane> get copyWith => _$BridgeLaneError_NoLaneCopyWithImpl<BridgeLaneError_NoLane>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeLaneError_NoLane&&(identical(other.msg, msg) || other.msg == msg));
}


@override
int get hashCode => Object.hash(runtimeType,msg);

@override
String toString() {
  return 'BridgeLaneError.noLane(msg: $msg)';
}


}

/// @nodoc
abstract mixin class $BridgeLaneError_NoLaneCopyWith<$Res> implements $BridgeLaneErrorCopyWith<$Res> {
  factory $BridgeLaneError_NoLaneCopyWith(BridgeLaneError_NoLane value, $Res Function(BridgeLaneError_NoLane) _then) = _$BridgeLaneError_NoLaneCopyWithImpl;
@useResult
$Res call({
 String msg
});




}
/// @nodoc
class _$BridgeLaneError_NoLaneCopyWithImpl<$Res>
    implements $BridgeLaneError_NoLaneCopyWith<$Res> {
  _$BridgeLaneError_NoLaneCopyWithImpl(this._self, this._then);

  final BridgeLaneError_NoLane _self;
  final $Res Function(BridgeLaneError_NoLane) _then;

/// Create a copy of BridgeLaneError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? msg = null,}) {
  return _then(BridgeLaneError_NoLane(
msg: null == msg ? _self.msg : msg // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class BridgeLaneError_UnsupportedLane extends BridgeLaneError {
  const BridgeLaneError_UnsupportedLane({required this.kind}): super._();
  

 final  String kind;

/// Create a copy of BridgeLaneError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeLaneError_UnsupportedLaneCopyWith<BridgeLaneError_UnsupportedLane> get copyWith => _$BridgeLaneError_UnsupportedLaneCopyWithImpl<BridgeLaneError_UnsupportedLane>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeLaneError_UnsupportedLane&&(identical(other.kind, kind) || other.kind == kind));
}


@override
int get hashCode => Object.hash(runtimeType,kind);

@override
String toString() {
  return 'BridgeLaneError.unsupportedLane(kind: $kind)';
}


}

/// @nodoc
abstract mixin class $BridgeLaneError_UnsupportedLaneCopyWith<$Res> implements $BridgeLaneErrorCopyWith<$Res> {
  factory $BridgeLaneError_UnsupportedLaneCopyWith(BridgeLaneError_UnsupportedLane value, $Res Function(BridgeLaneError_UnsupportedLane) _then) = _$BridgeLaneError_UnsupportedLaneCopyWithImpl;
@useResult
$Res call({
 String kind
});




}
/// @nodoc
class _$BridgeLaneError_UnsupportedLaneCopyWithImpl<$Res>
    implements $BridgeLaneError_UnsupportedLaneCopyWith<$Res> {
  _$BridgeLaneError_UnsupportedLaneCopyWithImpl(this._self, this._then);

  final BridgeLaneError_UnsupportedLane _self;
  final $Res Function(BridgeLaneError_UnsupportedLane) _then;

/// Create a copy of BridgeLaneError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? kind = null,}) {
  return _then(BridgeLaneError_UnsupportedLane(
kind: null == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$BridgeLanePromptOutcome {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeLanePromptOutcome);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'BridgeLanePromptOutcome()';
}


}

/// @nodoc
class $BridgeLanePromptOutcomeCopyWith<$Res>  {
$BridgeLanePromptOutcomeCopyWith(BridgeLanePromptOutcome _, $Res Function(BridgeLanePromptOutcome) __);
}


/// Adds pattern-matching-related methods to [BridgeLanePromptOutcome].
extension BridgeLanePromptOutcomePatterns on BridgeLanePromptOutcome {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeLanePromptOutcome_None value)?  none,TResult Function( BridgeLanePromptOutcome_Accepted value)?  accepted,TResult Function( BridgeLanePromptOutcome_Unknown value)?  unknown,TResult Function( BridgeLanePromptOutcome_Refused value)?  refused,TResult Function( BridgeLanePromptOutcome_Other value)?  other,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeLanePromptOutcome_None() when none != null:
return none(_that);case BridgeLanePromptOutcome_Accepted() when accepted != null:
return accepted(_that);case BridgeLanePromptOutcome_Unknown() when unknown != null:
return unknown(_that);case BridgeLanePromptOutcome_Refused() when refused != null:
return refused(_that);case BridgeLanePromptOutcome_Other() when other != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeLanePromptOutcome_None value)  none,required TResult Function( BridgeLanePromptOutcome_Accepted value)  accepted,required TResult Function( BridgeLanePromptOutcome_Unknown value)  unknown,required TResult Function( BridgeLanePromptOutcome_Refused value)  refused,required TResult Function( BridgeLanePromptOutcome_Other value)  other,}){
final _that = this;
switch (_that) {
case BridgeLanePromptOutcome_None():
return none(_that);case BridgeLanePromptOutcome_Accepted():
return accepted(_that);case BridgeLanePromptOutcome_Unknown():
return unknown(_that);case BridgeLanePromptOutcome_Refused():
return refused(_that);case BridgeLanePromptOutcome_Other():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeLanePromptOutcome_None value)?  none,TResult? Function( BridgeLanePromptOutcome_Accepted value)?  accepted,TResult? Function( BridgeLanePromptOutcome_Unknown value)?  unknown,TResult? Function( BridgeLanePromptOutcome_Refused value)?  refused,TResult? Function( BridgeLanePromptOutcome_Other value)?  other,}){
final _that = this;
switch (_that) {
case BridgeLanePromptOutcome_None() when none != null:
return none(_that);case BridgeLanePromptOutcome_Accepted() when accepted != null:
return accepted(_that);case BridgeLanePromptOutcome_Unknown() when unknown != null:
return unknown(_that);case BridgeLanePromptOutcome_Refused() when refused != null:
return refused(_that);case BridgeLanePromptOutcome_Other() when other != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  none,TResult Function()?  accepted,TResult Function()?  unknown,TResult Function()?  refused,TResult Function( String raw)?  other,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeLanePromptOutcome_None() when none != null:
return none();case BridgeLanePromptOutcome_Accepted() when accepted != null:
return accepted();case BridgeLanePromptOutcome_Unknown() when unknown != null:
return unknown();case BridgeLanePromptOutcome_Refused() when refused != null:
return refused();case BridgeLanePromptOutcome_Other() when other != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  none,required TResult Function()  accepted,required TResult Function()  unknown,required TResult Function()  refused,required TResult Function( String raw)  other,}) {final _that = this;
switch (_that) {
case BridgeLanePromptOutcome_None():
return none();case BridgeLanePromptOutcome_Accepted():
return accepted();case BridgeLanePromptOutcome_Unknown():
return unknown();case BridgeLanePromptOutcome_Refused():
return refused();case BridgeLanePromptOutcome_Other():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  none,TResult? Function()?  accepted,TResult? Function()?  unknown,TResult? Function()?  refused,TResult? Function( String raw)?  other,}) {final _that = this;
switch (_that) {
case BridgeLanePromptOutcome_None() when none != null:
return none();case BridgeLanePromptOutcome_Accepted() when accepted != null:
return accepted();case BridgeLanePromptOutcome_Unknown() when unknown != null:
return unknown();case BridgeLanePromptOutcome_Refused() when refused != null:
return refused();case BridgeLanePromptOutcome_Other() when other != null:
return other(_that.raw);case _:
  return null;

}
}

}

/// @nodoc


class BridgeLanePromptOutcome_None extends BridgeLanePromptOutcome {
  const BridgeLanePromptOutcome_None(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeLanePromptOutcome_None);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'BridgeLanePromptOutcome.none()';
}


}




/// @nodoc


class BridgeLanePromptOutcome_Accepted extends BridgeLanePromptOutcome {
  const BridgeLanePromptOutcome_Accepted(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeLanePromptOutcome_Accepted);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'BridgeLanePromptOutcome.accepted()';
}


}




/// @nodoc


class BridgeLanePromptOutcome_Unknown extends BridgeLanePromptOutcome {
  const BridgeLanePromptOutcome_Unknown(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeLanePromptOutcome_Unknown);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'BridgeLanePromptOutcome.unknown()';
}


}




/// @nodoc


class BridgeLanePromptOutcome_Refused extends BridgeLanePromptOutcome {
  const BridgeLanePromptOutcome_Refused(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeLanePromptOutcome_Refused);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'BridgeLanePromptOutcome.refused()';
}


}




/// @nodoc


class BridgeLanePromptOutcome_Other extends BridgeLanePromptOutcome {
  const BridgeLanePromptOutcome_Other({required this.raw}): super._();
  

 final  String raw;

/// Create a copy of BridgeLanePromptOutcome
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeLanePromptOutcome_OtherCopyWith<BridgeLanePromptOutcome_Other> get copyWith => _$BridgeLanePromptOutcome_OtherCopyWithImpl<BridgeLanePromptOutcome_Other>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeLanePromptOutcome_Other&&(identical(other.raw, raw) || other.raw == raw));
}


@override
int get hashCode => Object.hash(runtimeType,raw);

@override
String toString() {
  return 'BridgeLanePromptOutcome.other(raw: $raw)';
}


}

/// @nodoc
abstract mixin class $BridgeLanePromptOutcome_OtherCopyWith<$Res> implements $BridgeLanePromptOutcomeCopyWith<$Res> {
  factory $BridgeLanePromptOutcome_OtherCopyWith(BridgeLanePromptOutcome_Other value, $Res Function(BridgeLanePromptOutcome_Other) _then) = _$BridgeLanePromptOutcome_OtherCopyWithImpl;
@useResult
$Res call({
 String raw
});




}
/// @nodoc
class _$BridgeLanePromptOutcome_OtherCopyWithImpl<$Res>
    implements $BridgeLanePromptOutcome_OtherCopyWith<$Res> {
  _$BridgeLanePromptOutcome_OtherCopyWithImpl(this._self, this._then);

  final BridgeLanePromptOutcome_Other _self;
  final $Res Function(BridgeLanePromptOutcome_Other) _then;

/// Create a copy of BridgeLanePromptOutcome
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? raw = null,}) {
  return _then(BridgeLanePromptOutcome_Other(
raw: null == raw ? _self.raw : raw // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$BridgeLaneProviderState {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeLaneProviderState);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'BridgeLaneProviderState()';
}


}

/// @nodoc
class $BridgeLaneProviderStateCopyWith<$Res>  {
$BridgeLaneProviderStateCopyWith(BridgeLaneProviderState _, $Res Function(BridgeLaneProviderState) __);
}


/// Adds pattern-matching-related methods to [BridgeLaneProviderState].
extension BridgeLaneProviderStatePatterns on BridgeLaneProviderState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeLaneProviderState_Ready value)?  ready,TResult Function( BridgeLaneProviderState_NeedsSetup value)?  needsSetup,TResult Function( BridgeLaneProviderState_Unavailable value)?  unavailable,TResult Function( BridgeLaneProviderState_Other value)?  other,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeLaneProviderState_Ready() when ready != null:
return ready(_that);case BridgeLaneProviderState_NeedsSetup() when needsSetup != null:
return needsSetup(_that);case BridgeLaneProviderState_Unavailable() when unavailable != null:
return unavailable(_that);case BridgeLaneProviderState_Other() when other != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeLaneProviderState_Ready value)  ready,required TResult Function( BridgeLaneProviderState_NeedsSetup value)  needsSetup,required TResult Function( BridgeLaneProviderState_Unavailable value)  unavailable,required TResult Function( BridgeLaneProviderState_Other value)  other,}){
final _that = this;
switch (_that) {
case BridgeLaneProviderState_Ready():
return ready(_that);case BridgeLaneProviderState_NeedsSetup():
return needsSetup(_that);case BridgeLaneProviderState_Unavailable():
return unavailable(_that);case BridgeLaneProviderState_Other():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeLaneProviderState_Ready value)?  ready,TResult? Function( BridgeLaneProviderState_NeedsSetup value)?  needsSetup,TResult? Function( BridgeLaneProviderState_Unavailable value)?  unavailable,TResult? Function( BridgeLaneProviderState_Other value)?  other,}){
final _that = this;
switch (_that) {
case BridgeLaneProviderState_Ready() when ready != null:
return ready(_that);case BridgeLaneProviderState_NeedsSetup() when needsSetup != null:
return needsSetup(_that);case BridgeLaneProviderState_Unavailable() when unavailable != null:
return unavailable(_that);case BridgeLaneProviderState_Other() when other != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  ready,TResult Function()?  needsSetup,TResult Function()?  unavailable,TResult Function( String raw)?  other,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeLaneProviderState_Ready() when ready != null:
return ready();case BridgeLaneProviderState_NeedsSetup() when needsSetup != null:
return needsSetup();case BridgeLaneProviderState_Unavailable() when unavailable != null:
return unavailable();case BridgeLaneProviderState_Other() when other != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  ready,required TResult Function()  needsSetup,required TResult Function()  unavailable,required TResult Function( String raw)  other,}) {final _that = this;
switch (_that) {
case BridgeLaneProviderState_Ready():
return ready();case BridgeLaneProviderState_NeedsSetup():
return needsSetup();case BridgeLaneProviderState_Unavailable():
return unavailable();case BridgeLaneProviderState_Other():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  ready,TResult? Function()?  needsSetup,TResult? Function()?  unavailable,TResult? Function( String raw)?  other,}) {final _that = this;
switch (_that) {
case BridgeLaneProviderState_Ready() when ready != null:
return ready();case BridgeLaneProviderState_NeedsSetup() when needsSetup != null:
return needsSetup();case BridgeLaneProviderState_Unavailable() when unavailable != null:
return unavailable();case BridgeLaneProviderState_Other() when other != null:
return other(_that.raw);case _:
  return null;

}
}

}

/// @nodoc


class BridgeLaneProviderState_Ready extends BridgeLaneProviderState {
  const BridgeLaneProviderState_Ready(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeLaneProviderState_Ready);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'BridgeLaneProviderState.ready()';
}


}




/// @nodoc


class BridgeLaneProviderState_NeedsSetup extends BridgeLaneProviderState {
  const BridgeLaneProviderState_NeedsSetup(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeLaneProviderState_NeedsSetup);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'BridgeLaneProviderState.needsSetup()';
}


}




/// @nodoc


class BridgeLaneProviderState_Unavailable extends BridgeLaneProviderState {
  const BridgeLaneProviderState_Unavailable(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeLaneProviderState_Unavailable);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'BridgeLaneProviderState.unavailable()';
}


}




/// @nodoc


class BridgeLaneProviderState_Other extends BridgeLaneProviderState {
  const BridgeLaneProviderState_Other({required this.raw}): super._();
  

 final  String raw;

/// Create a copy of BridgeLaneProviderState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeLaneProviderState_OtherCopyWith<BridgeLaneProviderState_Other> get copyWith => _$BridgeLaneProviderState_OtherCopyWithImpl<BridgeLaneProviderState_Other>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeLaneProviderState_Other&&(identical(other.raw, raw) || other.raw == raw));
}


@override
int get hashCode => Object.hash(runtimeType,raw);

@override
String toString() {
  return 'BridgeLaneProviderState.other(raw: $raw)';
}


}

/// @nodoc
abstract mixin class $BridgeLaneProviderState_OtherCopyWith<$Res> implements $BridgeLaneProviderStateCopyWith<$Res> {
  factory $BridgeLaneProviderState_OtherCopyWith(BridgeLaneProviderState_Other value, $Res Function(BridgeLaneProviderState_Other) _then) = _$BridgeLaneProviderState_OtherCopyWithImpl;
@useResult
$Res call({
 String raw
});




}
/// @nodoc
class _$BridgeLaneProviderState_OtherCopyWithImpl<$Res>
    implements $BridgeLaneProviderState_OtherCopyWith<$Res> {
  _$BridgeLaneProviderState_OtherCopyWithImpl(this._self, this._then);

  final BridgeLaneProviderState_Other _self;
  final $Res Function(BridgeLaneProviderState_Other) _then;

/// Create a copy of BridgeLaneProviderState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? raw = null,}) {
  return _then(BridgeLaneProviderState_Other(
raw: null == raw ? _self.raw : raw // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$BridgeLaneSettingChange {

 String get id;
/// Create a copy of BridgeLaneSettingChange
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeLaneSettingChangeCopyWith<BridgeLaneSettingChange> get copyWith => _$BridgeLaneSettingChangeCopyWithImpl<BridgeLaneSettingChange>(this as BridgeLaneSettingChange, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeLaneSettingChange&&(identical(other.id, id) || other.id == id));
}


@override
int get hashCode => Object.hash(runtimeType,id);

@override
String toString() {
  return 'BridgeLaneSettingChange(id: $id)';
}


}

/// @nodoc
abstract mixin class $BridgeLaneSettingChangeCopyWith<$Res>  {
  factory $BridgeLaneSettingChangeCopyWith(BridgeLaneSettingChange value, $Res Function(BridgeLaneSettingChange) _then) = _$BridgeLaneSettingChangeCopyWithImpl;
@useResult
$Res call({
 String id
});




}
/// @nodoc
class _$BridgeLaneSettingChangeCopyWithImpl<$Res>
    implements $BridgeLaneSettingChangeCopyWith<$Res> {
  _$BridgeLaneSettingChangeCopyWithImpl(this._self, this._then);

  final BridgeLaneSettingChange _self;
  final $Res Function(BridgeLaneSettingChange) _then;

/// Create a copy of BridgeLaneSettingChange
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [BridgeLaneSettingChange].
extension BridgeLaneSettingChangePatterns on BridgeLaneSettingChange {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeLaneSettingChange_Model value)?  model,TResult Function( BridgeLaneSettingChange_Mode value)?  mode,TResult Function( BridgeLaneSettingChange_Config value)?  config,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeLaneSettingChange_Model() when model != null:
return model(_that);case BridgeLaneSettingChange_Mode() when mode != null:
return mode(_that);case BridgeLaneSettingChange_Config() when config != null:
return config(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeLaneSettingChange_Model value)  model,required TResult Function( BridgeLaneSettingChange_Mode value)  mode,required TResult Function( BridgeLaneSettingChange_Config value)  config,}){
final _that = this;
switch (_that) {
case BridgeLaneSettingChange_Model():
return model(_that);case BridgeLaneSettingChange_Mode():
return mode(_that);case BridgeLaneSettingChange_Config():
return config(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeLaneSettingChange_Model value)?  model,TResult? Function( BridgeLaneSettingChange_Mode value)?  mode,TResult? Function( BridgeLaneSettingChange_Config value)?  config,}){
final _that = this;
switch (_that) {
case BridgeLaneSettingChange_Model() when model != null:
return model(_that);case BridgeLaneSettingChange_Mode() when mode != null:
return mode(_that);case BridgeLaneSettingChange_Config() when config != null:
return config(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String id)?  model,TResult Function( String id)?  mode,TResult Function( String id,  String value,  String? forModel)?  config,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeLaneSettingChange_Model() when model != null:
return model(_that.id);case BridgeLaneSettingChange_Mode() when mode != null:
return mode(_that.id);case BridgeLaneSettingChange_Config() when config != null:
return config(_that.id,_that.value,_that.forModel);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String id)  model,required TResult Function( String id)  mode,required TResult Function( String id,  String value,  String? forModel)  config,}) {final _that = this;
switch (_that) {
case BridgeLaneSettingChange_Model():
return model(_that.id);case BridgeLaneSettingChange_Mode():
return mode(_that.id);case BridgeLaneSettingChange_Config():
return config(_that.id,_that.value,_that.forModel);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String id)?  model,TResult? Function( String id)?  mode,TResult? Function( String id,  String value,  String? forModel)?  config,}) {final _that = this;
switch (_that) {
case BridgeLaneSettingChange_Model() when model != null:
return model(_that.id);case BridgeLaneSettingChange_Mode() when mode != null:
return mode(_that.id);case BridgeLaneSettingChange_Config() when config != null:
return config(_that.id,_that.value,_that.forModel);case _:
  return null;

}
}

}

/// @nodoc


class BridgeLaneSettingChange_Model extends BridgeLaneSettingChange {
  const BridgeLaneSettingChange_Model({required this.id}): super._();
  

@override final  String id;

/// Create a copy of BridgeLaneSettingChange
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeLaneSettingChange_ModelCopyWith<BridgeLaneSettingChange_Model> get copyWith => _$BridgeLaneSettingChange_ModelCopyWithImpl<BridgeLaneSettingChange_Model>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeLaneSettingChange_Model&&(identical(other.id, id) || other.id == id));
}


@override
int get hashCode => Object.hash(runtimeType,id);

@override
String toString() {
  return 'BridgeLaneSettingChange.model(id: $id)';
}


}

/// @nodoc
abstract mixin class $BridgeLaneSettingChange_ModelCopyWith<$Res> implements $BridgeLaneSettingChangeCopyWith<$Res> {
  factory $BridgeLaneSettingChange_ModelCopyWith(BridgeLaneSettingChange_Model value, $Res Function(BridgeLaneSettingChange_Model) _then) = _$BridgeLaneSettingChange_ModelCopyWithImpl;
@override @useResult
$Res call({
 String id
});




}
/// @nodoc
class _$BridgeLaneSettingChange_ModelCopyWithImpl<$Res>
    implements $BridgeLaneSettingChange_ModelCopyWith<$Res> {
  _$BridgeLaneSettingChange_ModelCopyWithImpl(this._self, this._then);

  final BridgeLaneSettingChange_Model _self;
  final $Res Function(BridgeLaneSettingChange_Model) _then;

/// Create a copy of BridgeLaneSettingChange
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,}) {
  return _then(BridgeLaneSettingChange_Model(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class BridgeLaneSettingChange_Mode extends BridgeLaneSettingChange {
  const BridgeLaneSettingChange_Mode({required this.id}): super._();
  

@override final  String id;

/// Create a copy of BridgeLaneSettingChange
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeLaneSettingChange_ModeCopyWith<BridgeLaneSettingChange_Mode> get copyWith => _$BridgeLaneSettingChange_ModeCopyWithImpl<BridgeLaneSettingChange_Mode>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeLaneSettingChange_Mode&&(identical(other.id, id) || other.id == id));
}


@override
int get hashCode => Object.hash(runtimeType,id);

@override
String toString() {
  return 'BridgeLaneSettingChange.mode(id: $id)';
}


}

/// @nodoc
abstract mixin class $BridgeLaneSettingChange_ModeCopyWith<$Res> implements $BridgeLaneSettingChangeCopyWith<$Res> {
  factory $BridgeLaneSettingChange_ModeCopyWith(BridgeLaneSettingChange_Mode value, $Res Function(BridgeLaneSettingChange_Mode) _then) = _$BridgeLaneSettingChange_ModeCopyWithImpl;
@override @useResult
$Res call({
 String id
});




}
/// @nodoc
class _$BridgeLaneSettingChange_ModeCopyWithImpl<$Res>
    implements $BridgeLaneSettingChange_ModeCopyWith<$Res> {
  _$BridgeLaneSettingChange_ModeCopyWithImpl(this._self, this._then);

  final BridgeLaneSettingChange_Mode _self;
  final $Res Function(BridgeLaneSettingChange_Mode) _then;

/// Create a copy of BridgeLaneSettingChange
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,}) {
  return _then(BridgeLaneSettingChange_Mode(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class BridgeLaneSettingChange_Config extends BridgeLaneSettingChange {
  const BridgeLaneSettingChange_Config({required this.id, required this.value, this.forModel}): super._();
  

@override final  String id;
 final  String value;
 final  String? forModel;

/// Create a copy of BridgeLaneSettingChange
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeLaneSettingChange_ConfigCopyWith<BridgeLaneSettingChange_Config> get copyWith => _$BridgeLaneSettingChange_ConfigCopyWithImpl<BridgeLaneSettingChange_Config>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeLaneSettingChange_Config&&(identical(other.id, id) || other.id == id)&&(identical(other.value, value) || other.value == value)&&(identical(other.forModel, forModel) || other.forModel == forModel));
}


@override
int get hashCode => Object.hash(runtimeType,id,value,forModel);

@override
String toString() {
  return 'BridgeLaneSettingChange.config(id: $id, value: $value, forModel: $forModel)';
}


}

/// @nodoc
abstract mixin class $BridgeLaneSettingChange_ConfigCopyWith<$Res> implements $BridgeLaneSettingChangeCopyWith<$Res> {
  factory $BridgeLaneSettingChange_ConfigCopyWith(BridgeLaneSettingChange_Config value, $Res Function(BridgeLaneSettingChange_Config) _then) = _$BridgeLaneSettingChange_ConfigCopyWithImpl;
@override @useResult
$Res call({
 String id, String value, String? forModel
});




}
/// @nodoc
class _$BridgeLaneSettingChange_ConfigCopyWithImpl<$Res>
    implements $BridgeLaneSettingChange_ConfigCopyWith<$Res> {
  _$BridgeLaneSettingChange_ConfigCopyWithImpl(this._self, this._then);

  final BridgeLaneSettingChange_Config _self;
  final $Res Function(BridgeLaneSettingChange_Config) _then;

/// Create a copy of BridgeLaneSettingChange
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? value = null,Object? forModel = freezed,}) {
  return _then(BridgeLaneSettingChange_Config(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as String,forModel: freezed == forModel ? _self.forModel : forModel // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

/// @nodoc
mixin _$BridgeSourceOffline {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeSourceOffline);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'BridgeSourceOffline()';
}


}

/// @nodoc
class $BridgeSourceOfflineCopyWith<$Res>  {
$BridgeSourceOfflineCopyWith(BridgeSourceOffline _, $Res Function(BridgeSourceOffline) __);
}


/// Adds pattern-matching-related methods to [BridgeSourceOffline].
extension BridgeSourceOfflinePatterns on BridgeSourceOffline {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeSourceOffline_NotInstalled value)?  notInstalled,TResult Function( BridgeSourceOffline_TooOld value)?  tooOld,TResult Function( BridgeSourceOffline_Unreachable value)?  unreachable,TResult Function( BridgeSourceOffline_Failed value)?  failed,TResult Function( BridgeSourceOffline_Other value)?  other,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeSourceOffline_NotInstalled() when notInstalled != null:
return notInstalled(_that);case BridgeSourceOffline_TooOld() when tooOld != null:
return tooOld(_that);case BridgeSourceOffline_Unreachable() when unreachable != null:
return unreachable(_that);case BridgeSourceOffline_Failed() when failed != null:
return failed(_that);case BridgeSourceOffline_Other() when other != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeSourceOffline_NotInstalled value)  notInstalled,required TResult Function( BridgeSourceOffline_TooOld value)  tooOld,required TResult Function( BridgeSourceOffline_Unreachable value)  unreachable,required TResult Function( BridgeSourceOffline_Failed value)  failed,required TResult Function( BridgeSourceOffline_Other value)  other,}){
final _that = this;
switch (_that) {
case BridgeSourceOffline_NotInstalled():
return notInstalled(_that);case BridgeSourceOffline_TooOld():
return tooOld(_that);case BridgeSourceOffline_Unreachable():
return unreachable(_that);case BridgeSourceOffline_Failed():
return failed(_that);case BridgeSourceOffline_Other():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeSourceOffline_NotInstalled value)?  notInstalled,TResult? Function( BridgeSourceOffline_TooOld value)?  tooOld,TResult? Function( BridgeSourceOffline_Unreachable value)?  unreachable,TResult? Function( BridgeSourceOffline_Failed value)?  failed,TResult? Function( BridgeSourceOffline_Other value)?  other,}){
final _that = this;
switch (_that) {
case BridgeSourceOffline_NotInstalled() when notInstalled != null:
return notInstalled(_that);case BridgeSourceOffline_TooOld() when tooOld != null:
return tooOld(_that);case BridgeSourceOffline_Unreachable() when unreachable != null:
return unreachable(_that);case BridgeSourceOffline_Failed() when failed != null:
return failed(_that);case BridgeSourceOffline_Other() when other != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  notInstalled,TResult Function()?  tooOld,TResult Function()?  unreachable,TResult Function()?  failed,TResult Function( String raw)?  other,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeSourceOffline_NotInstalled() when notInstalled != null:
return notInstalled();case BridgeSourceOffline_TooOld() when tooOld != null:
return tooOld();case BridgeSourceOffline_Unreachable() when unreachable != null:
return unreachable();case BridgeSourceOffline_Failed() when failed != null:
return failed();case BridgeSourceOffline_Other() when other != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  notInstalled,required TResult Function()  tooOld,required TResult Function()  unreachable,required TResult Function()  failed,required TResult Function( String raw)  other,}) {final _that = this;
switch (_that) {
case BridgeSourceOffline_NotInstalled():
return notInstalled();case BridgeSourceOffline_TooOld():
return tooOld();case BridgeSourceOffline_Unreachable():
return unreachable();case BridgeSourceOffline_Failed():
return failed();case BridgeSourceOffline_Other():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  notInstalled,TResult? Function()?  tooOld,TResult? Function()?  unreachable,TResult? Function()?  failed,TResult? Function( String raw)?  other,}) {final _that = this;
switch (_that) {
case BridgeSourceOffline_NotInstalled() when notInstalled != null:
return notInstalled();case BridgeSourceOffline_TooOld() when tooOld != null:
return tooOld();case BridgeSourceOffline_Unreachable() when unreachable != null:
return unreachable();case BridgeSourceOffline_Failed() when failed != null:
return failed();case BridgeSourceOffline_Other() when other != null:
return other(_that.raw);case _:
  return null;

}
}

}

/// @nodoc


class BridgeSourceOffline_NotInstalled extends BridgeSourceOffline {
  const BridgeSourceOffline_NotInstalled(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeSourceOffline_NotInstalled);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'BridgeSourceOffline.notInstalled()';
}


}




/// @nodoc


class BridgeSourceOffline_TooOld extends BridgeSourceOffline {
  const BridgeSourceOffline_TooOld(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeSourceOffline_TooOld);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'BridgeSourceOffline.tooOld()';
}


}




/// @nodoc


class BridgeSourceOffline_Unreachable extends BridgeSourceOffline {
  const BridgeSourceOffline_Unreachable(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeSourceOffline_Unreachable);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'BridgeSourceOffline.unreachable()';
}


}




/// @nodoc


class BridgeSourceOffline_Failed extends BridgeSourceOffline {
  const BridgeSourceOffline_Failed(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeSourceOffline_Failed);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'BridgeSourceOffline.failed()';
}


}




/// @nodoc


class BridgeSourceOffline_Other extends BridgeSourceOffline {
  const BridgeSourceOffline_Other({required this.raw}): super._();
  

 final  String raw;

/// Create a copy of BridgeSourceOffline
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeSourceOffline_OtherCopyWith<BridgeSourceOffline_Other> get copyWith => _$BridgeSourceOffline_OtherCopyWithImpl<BridgeSourceOffline_Other>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeSourceOffline_Other&&(identical(other.raw, raw) || other.raw == raw));
}


@override
int get hashCode => Object.hash(runtimeType,raw);

@override
String toString() {
  return 'BridgeSourceOffline.other(raw: $raw)';
}


}

/// @nodoc
abstract mixin class $BridgeSourceOffline_OtherCopyWith<$Res> implements $BridgeSourceOfflineCopyWith<$Res> {
  factory $BridgeSourceOffline_OtherCopyWith(BridgeSourceOffline_Other value, $Res Function(BridgeSourceOffline_Other) _then) = _$BridgeSourceOffline_OtherCopyWithImpl;
@useResult
$Res call({
 String raw
});




}
/// @nodoc
class _$BridgeSourceOffline_OtherCopyWithImpl<$Res>
    implements $BridgeSourceOffline_OtherCopyWith<$Res> {
  _$BridgeSourceOffline_OtherCopyWithImpl(this._self, this._then);

  final BridgeSourceOffline_Other _self;
  final $Res Function(BridgeSourceOffline_Other) _then;

/// Create a copy of BridgeSourceOffline
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? raw = null,}) {
  return _then(BridgeSourceOffline_Other(
raw: null == raw ? _self.raw : raw // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on

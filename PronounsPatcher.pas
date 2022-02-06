unit PronounsPatcher;
{
    Pronouns provides a 'they/them' option to players that allows them to exclude gendered content referencing their character.
    Some content was authored in such a way that the only path forward is to follow a gendered branch. This patcher detects those cases and patches a fallback in
    that allows the player to continue making progress at the expense of having to see that gendered content.
}

interface
implementation
uses xEditAPI;

const //CTDA Elements in order: (ComparisonType, *not sure*, ComparisionValue, ConditionFunction, *not sure*, Parameter1, Parameter2, RunOn, Reference, Parameter3)
ComparisonType = 0;
ComparisonValue = 2;
ConditionFunction = 3;
ReferenceableObject = 5;
ConditionParam1 = 6;
RunOn = 7;
Reference = 8;

var
pronounsPatch : IwbFile;
activePronounsGlobal : IwbRecord;
malePronounFallback : IwbRecord;
femalePronounFallback : IwbRecord;
playerREF : IwbElement;


procedure Initialize();
begin
    SetGlobalPronounFormsFromFile();

    if (not Assigned(malePronounFallback) or not Assigned(femalePronounFallback) or not Assigned(activePronounsGlobal)) then
    begin
        AddMessage('A valid Pronouns.esp appears to be missing. Please ensure it is included in your load order. Aborting patch operation.');
        exit;
    end;

    SetGlobalPlayerReference();

    PrepareNewPatchPlugin();    

    PatchFallbackIntoAllFiles();

    AddOutroMessage();
end;

function SetGlobalPronounFormsFromFile() : IwbElement;
var
    pronouns : IwbFile;
    pronounsGlobals : IwbGroupRecord;
begin
    pronouns := GetFileByName('Pronouns.esp');
    pronounsGlobals := GroupBySignature(pronouns, 'GLOB');

    activePronounsGlobal := MainRecordByEditorID(pronounsGlobals, '_PlayerActivePronouns');
    malePronounFallback := MainRecordByEditorID(pronounsGlobals, '_PlayerUseMaleFallbackPronouns');
    femalePronounFallback := MainRecordByEditorID(pronounsGlobals, '_PlayerUseFemaleFallbackPronouns');
end;

procedure SetGlobalPlayerReference();
begin
    playerREF := MainRecordByEditorID(GroupBySignature(GetFileByName('Skyrim.esm'), 'NPC_'), 'Player');
end;

procedure AddOutroMessage();
begin
    AddMessage(' ');
    AddMessage('PronounsPatch.esp built. The records listed above can be better acounted for by manually adding new gender-neutral fallbacks.');
    AddMessage('Be sure to save and close xEdit, then activate the plugin to see the changes in-game.');
    AddMessage(' ');
end;

procedure PrepareNewPatchPlugin();
begin
    GetOrCreatePatchPlugin();
    ConfigurePatchPlugin();
end;

procedure GetOrCreatePatchPlugin();
begin
    pronounsPatch := GetFileByName('PronounsPatch.esp');

    if not Assigned(pronounsPatch) then
    begin
        pronounsPatch := AddNewFileName('PronounsPatch.esp');
    end;
end;

function GetFileByName(fileName : string) : IwbFile;
var
   fileIterator: integer;
   tempFile: IwbFile;
begin
    for fileIterator := 0 to FileCount - 1 do
    begin
        tempFile := FileByIndex(fileIterator);        

        if (GetFileName(tempFile) = fileName) then 
        begin
            result := tempFile;
            exit;
        end;
    end;
end;

procedure ConfigurePatchPlugin();
begin
    ClearPatchRecords();
    ResetPatchMasters();
    AddGlobalPronounFormsToPatchPlugin();
end;

procedure ClearPatchRecords();
begin
    AddMessage('Clearing previous patch records...');

    Remove(GroupBySignature(pronounsPatch, 'DIAL'));
end;

procedure ResetPatchMasters();
begin
    CleanMasters(pronounsPatch);
    AddMasterIfMissing(pronounsPatch, 'Skyrim.esm');
    AddMasterIfMissing(pronounsPatch, 'Pronouns.esp');
end;

procedure AddGlobalPronounFormsToPatchPlugin();
begin
    wbCopyElementToFile(activePronounsGlobal, pronounsPatch, false, true);
    wbCopyElementToFile(malePronounFallback, pronounsPatch, false, true);
    wbCopyElementToFile(femalePronounFallback, pronounsPatch, false, true);
end;

procedure PatchFallbackIntoAllFiles();
var
    i : integer;
begin
    for i:= 0 to (FileCount - 1) do
    begin
        PatchFallbackIntoFile(FileByIndex(i));
    end;
end;

procedure PatchFallbackIntoFile(currentFile : IwbFile);
begin
    if (Equals(currentFile, pronounsPatch)) then
    begin
        exit;
    end;

    AddMessage(' '); //new line
    AddMessage('Evaluating File: ' + GetFileName(currentFile) + '. Records listed below may need patching.');

    PatchRequiredGenderedDialogue(currentFile);

end;

procedure PatchRequiredGenderedDialogue(currentFile : IwbFile);
var
    allDialogueTopics : IwbGroupRecord;
begin
    if (HasGroup(currentFile, 'DIAL') = false) then
    begin
        exit;
    end;

    allDialogueTopics := GroupBySignature(currentFile, 'DIAL');

    PatchDialogueElementsInGroup(allDialogueTopics);
end;

procedure PatchDialogueElementsInGroup(dialGroup : IwbGroupRecord);
var
    i : integer;
    lastDialElementIndex : integer;    
    dialElement : IwbElement;
begin
    lastDialElementIndex := ElementCount(dialGroup) - 1;

    for i:= 0 to lastDialElementIndex do
    begin
        dialElement := ElementByIndex(dialGroup, i);
        PatchDialogueElement(dialElement);
    end;
end;

procedure PatchDialogueElement(dialElement : IwbElement);
var
    allPossibleLinesUnderElement : IwbGroupRecord;
begin
    if IsWinningOverride(dialElement) = false then
        exit;

    allPossibleLinesUnderElement := ChildGroup(dialElement);
    PatchFallbackIntoDeadlockableGroup(allPossibleLinesUnderElement);
end;

procedure PatchFallbackIntoDeadlockableGroup(group : IwbGroupRecord);
var
    requiredGetSexBitfields: TList;
begin
    requiredGetSexBitfields := GetListOfRequiredGetSexBitfieldsInElements(group);

    if (IsGetSexRequiredForAllElements(requiredGetSexBitfields)) then
    begin
        AddElementMastersIfMissing(group);
        AddMessage(BaseName(group)); //log out the groups that require GetSex

        PatchRequiredGetSexConditionsInElements(group, requiredGetSexBitfields);
    end;      

    requiredGetSexBitfields.Free;
end;

procedure PatchFallbackIntoDeadlockableElement(element : IwbElement);
var
    requiredGetSexBitfield: integer;
begin
    requiredGetSexBitfield := GetRequiredGetSexBitfield(element);

    if (requiredGetSexBitfield <> 0) then
    begin
        AddElementMastersIfMissing(element);
        AddMessage(BaseName(element)); //log out the elements that require GetSex

        element := CopyElementOverrideIntoPatch(element);
        PatchRequiredGetSexConditionsInElement(element, requiredGetSexBitfield);
    end;      
end;

procedure AddElementMastersIfMissing(element : IwbElement);
var
    i : integer;
    parentFile : IwbFile;
begin
    parentFile := GetFile(element);

    for i:= 0 to MasterCount(parentFile) - 1 do
    begin
        AddMasterIfMissing(pronounsPatch, BaseName(MasterByIndex(parentFile, i)));
    end;

    AddMasterIfMissing(pronounsPatch, BaseName(parentFile));
end;

function GetListOfRequiredGetSexBitfieldsInElements(elementGroup : IwbGroupRecord) : TList;
var
    i, lastElementIndex : integer;
    requiredGetSexBitfields: TList;
    element : IwbElement;
begin    
    lastElementIndex := ElementCount(elementGroup) - 1;
    requiredGetSexBitfields := TList.create;
    requiredGetSexBitfields.Capacity := lastElementIndex + 1;

    for i:= 0 to lastElementIndex do
    begin
        element := ElementByIndex(elementGroup, i);
        requiredGetSexBitfields.Add(GetRequiredGetSexBitfield(element));
    end;

    result := requiredGetSexBitfields;
end;

function GetRequiredGetSexBitfield(element : IwbElement) : integer;
var
    conditions: IwbGroupRecord;
begin
    conditions := ElementByName(element, 'Conditions');
    result := GetRequiredGetSexBitfieldFromConditions(conditions);
end;

function GetRequiredGetSexBitfieldFromConditions(conditions : IwbElement) : integer;
var
    i, lastConditionIndex : integer;

    requiresGetSexBit : boolean;
    conditionAttributes, prevConditionAttributes, getSexBitfield : integer;
begin
    lastConditionIndex := ElementCount(conditions) - 1;

    for i:= 0 to lastConditionIndex do
    begin
        conditionAttributes := GetConditionAttributeBitfield(conditions, i);

        requiresGetSexBit := IsConditionRequiredGetSexOperation(conditionAttributes, prevConditionAttributes);
        getSexBitfield := getSexBitfield + (BoolToInt(requiresGetSexBit) shl i);

        prevConditionAttributes := conditionAttributes;
    end;

    result := getSexBitfield;
end;

function GetConditionAttributeBitfield(conditions : IwbElement; conditionIndex : integer) : integer;
var
    conditionData : IwbElement;
    firstBit, secondBit, thirdBit : integer;
    conditionAttributeBitfield : integer;
begin
    conditionData := GetConditionDataFromConditions(conditions, conditionIndex);

    firstBit := BoolToInt(IsConditionOR(conditionData));
    secondBit := BoolToInt(IsConditionGetSexOperation(conditionData));
    thirdBit := BoolToInt(conditionIndex = (ElementCount(conditions) - 1));

    conditionAttributeBitfield := firstBit + (secondBit shl 1) + (thirdBit shl 2);

    result := conditionAttributeBitfield;
end;

function GetConditionDataFromConditions(conditions : IwbElement; conditionIndex : integer) : IwbElement;
var
    currentCondition : IwbElement;
begin
    currentCondition := ElementByIndex(conditions, conditionIndex);
    result := ElementBySignature(currentCondition, 'CTDA');
end;

function IsConditionOR(conditionData : IwbElement) : boolean;
var
    currentComparisonType : integer;
begin
    currentComparisonType := GetNativeValue(ElementByIndex(conditionData, ComparisonType));
    result := (currentComparisonType and 1) = 1; //first bit appears to be OR flag
end;

function IsConditionGetSexOperation(conditionData : IwbElement) : boolean;
var
    currentConditionFunction : string;
begin
    currentConditionFunction := GetEditValue(ElementByIndex(conditionData, ConditionFunction));
    result := ((currentConditionFunction = 'GetIsSex') or (currentConditionFunction = 'GetPCIsSex'));
end;

function IsConditionRequiredGetSexOperation(currentConditionAttributes : integer; prevConditionAttributes : integer) : boolean;
begin
    if (((IsConditionAttributeLastCondition(currentConditionAttributes)) or (IsConditionAttributeAND(currentConditionAttributes))) and IsConditionAttributeGetSex(currentConditionAttributes)) then
    begin
        result := IsConditionAttributeAND(prevConditionAttributes);
    end;
end;

function IsConditionAttributeLastCondition(conditionAttributeBitfield : integer) : boolean;
begin
    result := (conditionAttributeBitfield shr 2) = 1;
end;

function IsConditionAttributeAND(conditionAttributeBitfield : integer): boolean;
begin
    result := not(IsConditionAttributeOR(conditionAttributeBitfield));
end;

function IsConditionAttributeOR(conditionAttributeBitfield : integer): boolean;
begin
    result := (conditionAttributeBitfield and 1) = 1;
end;

function IsConditionAttributeGetSex(conditionAttributeBitfield : integer): boolean;
begin
    result := ((conditionAttributeBitfield and 2) shr 1) = 1;
end;

function IsGetSexRequiredForAllElements(requiredGetSexBitfields : TList) : boolean;
var
    i : integer;
    exemptLeadingElementsFinished : boolean;
begin
    result := requiredGetSexBitfields.Count <> 0;

    for i:= 0 to requiredGetSexBitfields.Count - 1 do
    begin
        if ((Integer(requiredGetSexBitfields[i]) <> 0) or (requiredGetSexBitfields.Count = 1)) then
            exemptLeadingElementsFinished := true;

        if ((exemptLeadingElementsFinished or (i = (requiredGetSexBitfields.Count - 1))) and (Integer(requiredGetSexBitfields[i]) = 0)) then
        begin
            result := false;
            exit;
        end;
    end;
end;

procedure PatchRequiredGetSexConditionsInElements(elementGroup : IwbGroupRecord; requiredGetSexBitfields: Tlist);
var
    i : integer;
    element : IwbElement;
begin
    for i:= 0 to ElementCount(elementGroup) - 1 do
    begin
        element := CopyElementOverrideIntoPatch(ElementByIndex(elementGroup, i));
        PatchRequiredGetSexConditionsInElement(element, Integer(requiredGetSexBitfields[i]));
    end;
end;

procedure PatchRequiredGetSexConditionsInElement(element : IwbElement; requiredGetSexBitfield : integer);
var
    currentConditionIndex, lastConditionIndex : integer;
    conditions: IwbGroupRecord;
begin
    conditions := ElementByName(element, 'Conditions');
    lastConditionIndex := ElementCount(conditions) - 1;

    for currentConditionIndex := lastConditionIndex DownTo 0 do
    begin
        if (IsRequiredGetSexBitAtIndex(requiredGetSexBitfield, currentConditionIndex) = true) then
        begin
            PatchRequiredGetSexCondition(conditions, currentConditionIndex);           
        end;
    end;
end;

function CopyElementOverrideIntoPatch(element : IwbElement) : IwbElement;
begin
    result := wbCopyElementToFile(element, pronounsPatch, false, true);
end;

function IsRequiredGetSexBitAtIndex(requiredGetSexBitfield : integer; conditionIndex : integer) : boolean;
begin
    result := (((requiredGetSexBitfield shr conditionIndex) and 1) = 1);
end;

procedure PatchRequiredGetSexCondition(conditions : IwbElement; conditionIndex : integer);
var
    currentCondition: IwbElement;
begin
    currentCondition := ElementByIndex(conditions, conditionIndex);

    InsertIsTheyThemActiveORCondition(conditions, currentCondition);
    InsertDuplicateGetSexANDCondition(conditions, currentCondition);
    InsertIsPlayerORCondition(conditions, currentCondition);
    InsertDuplicateGetSexANDCondition(conditions, currentCondition);
    InsertGlobalFallbackORCondition(conditions, currentCondition);
end;

procedure InsertIsTheyThemActiveORCondition(conditions : IwbGroupRecord; condition : IwbElement);
var
    isPlayerORCondition : IwbElement;
    conditionData : IwbElement;
begin
    isPlayerORCondition := DuplicateCondition(conditions, condition);
    conditionData := ElementBySignature(isPlayerORCondition, 'CTDA');

    SetConditionFunction(conditionData, 'GetGlobalValue');
    SetConditionReferenceableObject(conditionData, GetEditValue(activePronounsGlobal));
    SetConditionComparisonType(conditionData, '1');
    SetConditionComparisonValue(conditionData, '2');
    SetConditionOR(conditionData);

end;

procedure InsertIsPlayerORCondition(conditions : IwbGroupRecord; condition : IwbElement);
var
    isPlayerORCondition : IwbElement;
    conditionData : IwbElement;
begin
    isPlayerORCondition := DuplicateCondition(conditions, condition);
    conditionData := ElementBySignature(isPlayerORCondition, 'CTDA');

    SetConditionFunction(conditionData, 'GetIsID');
    SetConditionReferenceableObject(conditionData, GetEditValue(playerREF));
    SetConditionComparisonType(conditionData, '1');
    SetConditionComparisonValue(conditionData, '1');
    SetConditionOR(conditionData);
end;

procedure InsertDuplicateGetSexANDCondition(conditions : IwbGroupRecord; condition : IwbElement);
var
    getSexANDCondition : IwbElement;
    conditionData : IwbElement;
begin
    getSexANDCondition := DuplicateCondition(conditions, condition);
    conditionData := ElementBySignature(getSexANDCondition, 'CTDA');

    SetConditionAND(conditionData);
end;

procedure InsertGlobalFallbackORCondition(conditions : IwbGroupRecord; condition : IwbElement);
var
    fallbackCondition, conditionData, fallbackGlobal : IwbElement;
    currentTargetedSex : string;
begin
    fallbackCondition := DuplicateCondition(conditions, condition);
    conditionData := ElementBySignature(fallbackCondition, 'CTDA');
    currentTargetedSex := GetEditValue(ElementByIndex(conditionData, ReferenceableObject));

    fallbackGlobal := malePronounFallback;
    if (currentTargetedSex = 'Female') then
    begin
        fallbackGlobal := femalePronounFallback;
    end;

    SetConditionFunction(conditionData, 'GetGlobalValue');
    SetConditionReferenceableObject(conditionData, GetEditValue(fallbackGlobal));
    SetConditionOR(conditionData);
end;

function DuplicateCondition(conditions : IwbGroupRecord; condition : IwbElement) : IwbElement;
var
    newCondition : IwbElement;
begin
    newCondition := ElementAssign(conditions, 0, condition, false);
    InsertElement(conditions, IndexOf(conditions, condition), RemoveElement(conditions, newCondition));
    result := newCondition;
end;

procedure SetConditionFunction(conditionData : IwbElement; targetConditionFunction : string);
begin
    SetEditValue(ElementByIndex(conditionData, ConditionFunction), targetConditionFunction);
end;

procedure SetConditionReferenceableObject(conditionData : IwbElement; targetObject : string);
begin
    SetEditValue(ElementByIndex(conditionData, ReferenceableObject), targetObject);
end;

procedure SetConditionComparisonType(conditionData : IwbElement; targetType : string);
begin
    SetEditValue(ElementByIndex(conditionData, ComparisonType), targetType);
end;

procedure SetConditionComparisonValue(conditionData : IwbElement; targetValue : string);
begin
    SetEditValue(ElementByIndex(conditionData, ComparisonValue), targetValue);
end;

procedure SetConditionAND(conditionData : IwbElement);
var
    currentComparisonType : IwbElement;
    comparisonVal : integer;
begin
    currentComparisonType := ElementByIndex(conditionData, ComparisonType);

    comparisonVal := GetNativeValue(currentComparisonType);
    SetNativeValue(currentComparisonType, comparisonVal - (comparisonVal and 1));
end;

procedure SetConditionOR(conditionData : IwbElement);
var
    currentComparisonType : IwbElement;
    comparisonVal : integer;
begin
    currentComparisonType := ElementByIndex(conditionData, ComparisonType);

    comparisonVal := GetNativeValue(currentComparisonType);
    SetNativeValue(currentComparisonType, comparisonVal or 1);
end;

//necessary in pascal because true = -1
function BoolToInt(boolVal : boolean) : integer;
begin
    result := boolVal and 1; //if false, (0 and 1) = 0, if true (-1 and 1) = 1
end;

end.
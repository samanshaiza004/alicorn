param(
	[string]$Title = 'Alicorn',
	[string]$ExpectedInitialValue = 'Editable value',
	[string]$ProbeValue = 'UIA contract value',
	[int]$TimeoutSeconds = 10
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes

$Deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)

function Find-Window {
	$NameCondition = [Windows.Automation.PropertyCondition]::new([Windows.Automation.AutomationElement]::NameProperty, $Title)
	return [Windows.Automation.AutomationElement]::RootElement.FindFirst(
		[Windows.Automation.TreeScope]::Children,
		$NameCondition
	)
}

$Window = $null
while ([DateTime]::UtcNow -lt $Deadline -and $null -eq $Window) {
	$Window = Find-Window
	if ($null -eq $Window) { Start-Sleep -Milliseconds 200 }
}
if ($null -eq $Window) { throw "Could not find window '$Title'. Start run.ps1 first." }

function Find-ByNameAndType($Root, [string]$Name, $Type) {
	$NameCondition = [Windows.Automation.PropertyCondition]::new([Windows.Automation.AutomationElement]::NameProperty, $Name)
	$TypeCondition = [Windows.Automation.PropertyCondition]::new([Windows.Automation.AutomationElement]::ControlTypeProperty, $Type)
	$Condition = [Windows.Automation.AndCondition]::new($NameCondition, $TypeCondition)
	return $Root.FindFirst([Windows.Automation.TreeScope]::Descendants, $Condition)
}

function Find-ByName($Root, [string]$Name) {
	$NameCondition = [Windows.Automation.PropertyCondition]::new([Windows.Automation.AutomationElement]::NameProperty, $Name)
	return $Root.FindFirst([Windows.Automation.TreeScope]::Descendants, $NameCondition)
}

function Get-FixtureControls($Root) {
	$Controls = [pscustomobject]@{
		button = Find-ByNameAndType -Root $Root -Name 'Increment value' -Type ([Windows.Automation.ControlType]::Button)
		field = Find-ByNameAndType -Root $Root -Name 'Contract text field' -Type ([Windows.Automation.ControlType]::Edit)
		status = Find-ByName $Root 'Action count'
		toggle = Find-ByNameAndType -Root $Root -Name 'Toggle action disabled' -Type ([Windows.Automation.ControlType]::Button)
		guarded = Find-ByNameAndType -Root $Root -Name 'Guarded action' -Type ([Windows.Automation.ControlType]::Button)
	}
	if ($null -eq $Controls.button) { throw 'Named button was not exposed as a UIA Button.' }
	if ($null -eq $Controls.field) { throw 'Named text field was not exposed as a UIA Edit control.' }
	if ($null -eq $Controls.status) { throw 'Named action status was not exposed in the UIA tree.' }
	if ($null -eq $Controls.toggle) { throw 'Named disabled-state toggle was not exposed as a UIA Button.' }
	if ($null -eq $Controls.guarded) { throw 'Named guarded action was not exposed as a UIA Button.' }
	if ($Controls.status.Current.ControlType -ne [Windows.Automation.ControlType]::StatusBar -and
		$Controls.status.Current.ControlType -ne [Windows.Automation.ControlType]::Text) {
		throw "Action status had unexpected UIA role '$($Controls.status.Current.ControlType.ProgrammaticName)'."
	}
	return $Controls
}

function Get-AccessibleValue($Element) {
	if ($null -eq $Element) { return $null }
	$Pattern = $null
	if ($Element.TryGetCurrentPattern([Windows.Automation.ValuePattern]::Pattern, [ref]$Pattern)) {
		return $Pattern.Current.Value
	}
	$TextPattern = $null
	if ($Element.TryGetCurrentPattern([Windows.Automation.TextPattern]::Pattern, [ref]$TextPattern)) {
		$Text = $TextPattern.DocumentRange.GetText(-1).Trim()
		if (-not [string]::IsNullOrEmpty($Text)) { return $Text }
	}
	return $Element.Current.Name
}

function Get-Bounds($Element, [string]$Kind) {
	$Bounds = $Element.Current.BoundingRectangle
	if ($Bounds.IsEmpty -or $Bounds.Width -le 0 -or $Bounds.Height -le 0) {
		throw "$Kind has empty or nonpositive UIA bounds: $Bounds"
	}
	return [pscustomobject]@{
		left = [double]$Bounds.Left
		top = [double]$Bounds.Top
		width = [double]$Bounds.Width
		height = [double]$Bounds.Height
	}
}

function Get-ElementRecord([string]$Kind, $Element) {
	$Bounds = Get-Bounds $Element $Kind
	return [pscustomobject]@{
		kind = $Kind
		name = $Element.Current.Name
		controlType = $Element.Current.ControlType.ProgrammaticName
		value = Get-AccessibleValue $Element
		enabled = [bool]$Element.Current.IsEnabled
		focused = [bool]$Element.Current.HasKeyboardFocus
		bounds = $Bounds
	}
}

function Get-TrackedControls($Controls) {
	return @(
		[pscustomobject]@{ kind='button'; element=$Controls.button },
		[pscustomobject]@{ kind='field'; element=$Controls.field },
		[pscustomobject]@{ kind='status'; element=$Controls.status },
		[pscustomobject]@{ kind='toggle'; element=$Controls.toggle },
		[pscustomobject]@{ kind='guarded'; element=$Controls.guarded }
	)
}

function Invoke-ToggleAction {
	$CurrentWindow = Find-Window
	if ($null -eq $CurrentWindow) { throw "Window '$Title' disappeared before invoking the disabled-state toggle." }
	$Toggle = Find-ByNameAndType -Root $CurrentWindow -Name 'Toggle action disabled' -Type ([Windows.Automation.ControlType]::Button)
	if ($null -eq $Toggle) { throw 'Disabled-state toggle disappeared from the UIA tree.' }
	$InvokePattern = $null
	if (-not $Toggle.TryGetCurrentPattern([Windows.Automation.InvokePattern]::Pattern, [ref]$InvokePattern)) {
		throw 'Disabled-state toggle does not expose UIA InvokePattern.'
	}
	try { $InvokePattern.Invoke() }
	catch { throw "UIA InvokePattern.Invoke failed for the disabled-state toggle: $($_.Exception.Message)" }
}

function Wait-GuardedEnabled([bool]$Expected) {
	$StateDeadline = [DateTime]::UtcNow.AddSeconds(3)
	$LastState = 'unavailable'
	$LastError = $null
	while ([DateTime]::UtcNow -lt $StateDeadline) {
		try {
			$CurrentWindow = Find-Window
			if ($null -ne $CurrentWindow) {
				$CurrentGuarded = Find-ByNameAndType -Root $CurrentWindow -Name 'Guarded action' -Type ([Windows.Automation.ControlType]::Button)
				if ($null -ne $CurrentGuarded) {
					$LastState = [bool]$CurrentGuarded.Current.IsEnabled
					if ($LastState -eq $Expected) { return $CurrentGuarded }
				}
			}
		} catch {
			$LastError = $_.Exception.Message
		}
		Start-Sleep -Milliseconds 100
	}
	$Detail = if ($null -ne $LastError) { "; last UIA read error: $LastError" } else { '' }
	throw "Guarded action did not report IsEnabled=$Expected within 3 seconds (last state: $LastState)$Detail."
}

$Controls = Get-FixtureControls $Window
$InitialFieldValue = Get-AccessibleValue $Controls.field
if ($InitialFieldValue -ne $ExpectedInitialValue) {
	throw "Unexpected initial field value '$InitialFieldValue'; expected '$ExpectedInitialValue'."
}
if (-not $Controls.field.Current.IsEnabled) { throw 'Text field is disabled.' }
if (-not $Controls.guarded.Current.IsEnabled) { throw 'Guarded action was not initially enabled in UIA.' }

$TrackedBeforeResize = Get-TrackedControls $Controls
$ControlsBeforeResize = @($TrackedBeforeResize | ForEach-Object { Get-ElementRecord $_.kind $_.element })
$WindowBoundsBefore = $Window.Current.BoundingRectangle
if ($WindowBoundsBefore.IsEmpty -or $WindowBoundsBefore.Width -le 0 -or $WindowBoundsBefore.Height -le 0) {
	throw "Window has empty or nonpositive UIA bounds before resize: $WindowBoundsBefore"
}
$WindowBeforeEvidence = [pscustomobject]@{
	left = [double]$WindowBoundsBefore.Left
	top = [double]$WindowBoundsBefore.Top
	width = [double]$WindowBoundsBefore.Width
	height = [double]$WindowBoundsBefore.Height
}
$WindowTransformPattern = $null
if (-not $Window.TryGetCurrentPattern([Windows.Automation.TransformPattern]::Pattern, [ref]$WindowTransformPattern)) {
	throw 'Fixture window does not expose UIA TransformPattern; cannot resize it through the native accessibility API.'
}
if (-not $WindowTransformPattern.Current.CanResize) {
	throw 'Fixture window reports UIA TransformPattern.CanResize=false; native accessibility resize is unavailable.'
}
$TargetWidth = [Math]::Ceiling($WindowBeforeEvidence.width + 240)
$TargetHeight = [Math]::Ceiling($WindowBeforeEvidence.height + 140)
try { $WindowTransformPattern.Resize([double]$TargetWidth, [double]$TargetHeight) }
catch { throw "UIA TransformPattern.Resize to ${TargetWidth}x${TargetHeight} failed: $($_.Exception.Message)" }

$ResizeDeadline = [DateTime]::UtcNow.AddSeconds(5)
$WindowAfterEvidence = $null
$ControlsAfterResize = $null
$LastResizeError = $null
$FieldBoundsBefore = ($ControlsBeforeResize | Where-Object kind -eq 'field').bounds
while ([DateTime]::UtcNow -lt $ResizeDeadline) {
	Start-Sleep -Milliseconds 100
	try {
		$Window = Find-Window
		if ($null -eq $Window) { continue }
		$CurrentWindowBounds = $Window.Current.BoundingRectangle
		if ($CurrentWindowBounds.IsEmpty -or $CurrentWindowBounds.Width -le 0 -or $CurrentWindowBounds.Height -le 0) {
			throw 'Resized window temporarily reported empty bounds.'
		}
		$Controls = Get-FixtureControls $Window
		$TrackedAfterResize = Get-TrackedControls $Controls
		$CurrentFieldBounds = Get-Bounds $Controls.field 'field'
		if ($CurrentWindowBounds.Width -ge ($WindowBeforeEvidence.width + 120) -and
			$CurrentFieldBounds.width -ge ($FieldBoundsBefore.width + 100)) {
			$WindowAfterEvidence = [pscustomobject]@{
				left = [double]$CurrentWindowBounds.Left
				top = [double]$CurrentWindowBounds.Top
				width = [double]$CurrentWindowBounds.Width
				height = [double]$CurrentWindowBounds.Height
			}
			$ControlsAfterResize = @($TrackedAfterResize | ForEach-Object { Get-ElementRecord $_.kind $_.element })
			break
		}
	} catch {
		$LastResizeError = $_.Exception.Message
	}
}
if ($null -eq $WindowAfterEvidence -or $null -eq $ControlsAfterResize) {
	$LastWindowWidth = 'unavailable'
	$LastFieldWidth = 'unavailable'
	try {
		$Window = Find-Window
		if ($null -ne $Window) {
			$LastWindowWidth = [string]$Window.Current.BoundingRectangle.Width
			$LastControls = Get-FixtureControls $Window
			$LastFieldWidth = [string](Get-Bounds $LastControls.field 'field').width
		}
	} catch { $LastResizeError = $_.Exception.Message }
	$Detail = if ($null -ne $LastResizeError) { "; last UIA read error: $LastResizeError" } else { '' }
	throw "Native resize did not publish dynamic field bounds within 5 seconds. Window width before=$($WindowBeforeEvidence.width), after=$LastWindowWidth; field width before=$($FieldBoundsBefore.width), after=$LastFieldWidth$Detail."
}
$FieldBoundsAfter = ($ControlsAfterResize | Where-Object kind -eq 'field').bounds
$ChangedBounds = @()
foreach ($Before in $ControlsBeforeResize) {
	$After = $ControlsAfterResize | Where-Object kind -eq $Before.kind | Select-Object -First 1
	if ($null -eq $After) { continue }
	if ([Math]::Abs($Before.bounds.left - $After.bounds.left) -gt 1 -or
		[Math]::Abs($Before.bounds.top - $After.bounds.top) -gt 1 -or
		[Math]::Abs($Before.bounds.width - $After.bounds.width) -gt 1 -or
		[Math]::Abs($Before.bounds.height - $After.bounds.height) -gt 1) {
		$ChangedBounds += $Before.kind
	}
}
if ($ChangedBounds -notcontains 'field' -or $FieldBoundsAfter.width -lt ($FieldBoundsBefore.width + 100)) {
	throw "Resize changed no meaningful field bounds: before=$($FieldBoundsBefore | ConvertTo-Json -Compress), after=$($FieldBoundsAfter | ConvertTo-Json -Compress)."
}
$ResizeEvidence = [pscustomobject]@{
	method = 'UIA TransformPattern.Resize'
	requested = [pscustomobject]@{ width=$TargetWidth; height=$TargetHeight }
	windowBefore = $WindowBeforeEvidence
	windowAfter = $WindowAfterEvidence
	controlsBefore = $ControlsBeforeResize
	controlsAfter = $ControlsAfterResize
	changedControls = $ChangedBounds
}

$Window = Find-Window
if ($null -eq $Window) { throw "Window '$Title' disappeared after resize." }
$Controls = Get-FixtureControls $Window
$ElementEvidence = @(Get-TrackedControls $Controls | ForEach-Object { Get-ElementRecord $_.kind $_.element })
$Field = $Controls.field
$Button = $Controls.button
$Status = $Controls.status
$Toggle = $Controls.toggle
$Guarded = $Controls.guarded

$null = $Field.SetFocus()
Start-Sleep -Milliseconds 250
if (-not $Field.Current.HasKeyboardFocus) { throw 'Text field did not receive UIA keyboard focus.' }

$ValuePattern = $null
if (-not $Field.TryGetCurrentPattern([Windows.Automation.ValuePattern]::Pattern, [ref]$ValuePattern)) {
	throw 'Text field does not expose UIA ValuePattern, so editability cannot be verified.'
}
if ($ValuePattern.Current.IsReadOnly) { throw 'Text field reports UIA IsReadOnly=true.' }
$ValuePattern.SetValue($ProbeValue)
$ValueDeadline = [DateTime]::UtcNow.AddSeconds(3)
while ([DateTime]::UtcNow -lt $ValueDeadline -and (Get-AccessibleValue $Field) -ne $ProbeValue) {
	Start-Sleep -Milliseconds 100
}
if ((Get-AccessibleValue $Field) -ne $ProbeValue) { throw 'UIA SetValue did not update the exposed field value.' }

$BeforeStatus = [pscustomobject]@{
	name = $Status.Current.Name
	value = Get-AccessibleValue $Status
	helpText = $Status.Current.HelpText
	itemStatus = $Status.Current.ItemStatus
}
$BeforeStatusSignature = $BeforeStatus | ConvertTo-Json -Compress -Depth 4
if ($BeforeStatus.value -ne '0') { throw "Unexpected initial status value '$($BeforeStatus.value)'; expected '0'." }
$InvokePattern = $null
if (-not $Button.TryGetCurrentPattern([Windows.Automation.InvokePattern]::Pattern, [ref]$InvokePattern)) {
	throw 'Button does not expose UIA InvokePattern.'
}
$InvokePattern.Invoke()
$StatusDeadline = [DateTime]::UtcNow.AddSeconds(3)
$AfterStatus = $BeforeStatus
while ([DateTime]::UtcNow -lt $StatusDeadline -and ($AfterStatus | ConvertTo-Json -Compress -Depth 4) -eq $BeforeStatusSignature) {
	Start-Sleep -Milliseconds 100
	$Window = Find-Window
	$Status = (Get-FixtureControls $Window).status
	$AfterStatus = [pscustomobject]@{
		name = $Status.Current.Name
		value = Get-AccessibleValue $Status
		helpText = $Status.Current.HelpText
		itemStatus = $Status.Current.ItemStatus
	}
}
if (($AfterStatus | ConvertTo-Json -Compress -Depth 4) -eq $BeforeStatusSignature) {
	throw 'Invoking the button did not change any exposed status name/value properties.'
}
if ($AfterStatus.value -ne '1') { throw "Button action produced status '$($AfterStatus.value)'; expected '1'." }

$GuardedBefore = [bool]$Guarded.Current.IsEnabled
if (-not $GuardedBefore) { throw 'Guarded action unexpectedly became disabled before the state transition check.' }
Invoke-ToggleAction
$GuardedDisabledElement = Wait-GuardedEnabled $false
$GuardedDisabled = [bool]$GuardedDisabledElement.Current.IsEnabled
Invoke-ToggleAction
$GuardedReenabledElement = Wait-GuardedEnabled $true
$GuardedReenabled = [bool]$GuardedReenabledElement.Current.IsEnabled
if (-not $GuardedBefore -or $GuardedDisabled -or -not $GuardedReenabled) {
	throw "Unexpected guarded-action UIA state sequence: $GuardedBefore -> $GuardedDisabled -> $GuardedReenabled."
}

[pscustomobject]@{
	result = 'PASS'
	window = $Window.Current.Name
	fieldValueBefore = $InitialFieldValue
	fieldValueAfter = Get-AccessibleValue $Field
	fieldFocused = [bool]$Field.Current.HasKeyboardFocus
	elements = $ElementEvidence
	resize = $ResizeEvidence
	guardedAction = [pscustomobject]@{
		name = 'Guarded action'
		controlType = $GuardedReenabledElement.Current.ControlType.ProgrammaticName
		states = @($GuardedBefore, $GuardedDisabled, $GuardedReenabled)
		toggleAction = 'UIA InvokePattern.Invoke'
	}
	statusBefore = $BeforeStatus
	statusAfter = $AfterStatus
	action = 'UIA InvokePattern.Invoke'
} | ConvertTo-Json -Depth 8

[CmdletBinding()]
Param(
	[Parameter(Mandatory=$True, HelpMessage="Input data file with the contents of sys.columns for a specified table")]
	[ValidateNotNullOrEmpty()]
	[string]$sysColumnsContentsPath,

	[Parameter(Mandatory=$False, HelpMessage="Append collation name to the string-based column schema")]
	[bool]$appendCollationName = $True,

	[Parameter(Mandatory=$False, HelpMessage="Append nullability option ('NULL' or 'NOT NULL') to the column schema")]
	[bool]$appendNullabilityOption = $False,

	[Parameter(Mandatory=$False, HelpMessage="Append column index (ID from sys.columns) to the end of the column schema")]
	[bool]$appendColumnIndex = $True)

# Include common helper functions
. "$($PSScriptRoot)/../common/_common.ps1"

# All of the columns from sys.columns table, listed in order.
[string[]]$sysColumnsFields = @(
	"object_id",
	"name",
	"column_id",
	"system_type_id",
	"user_type_id",
	"max_length",
	"precision",
	"scale",
	"collation_name",
	"is_nullable",
	"is_ansi_padded",
	"is_rowguidcol",
	"is_identity",
	"is_computed",
	"is_filestream",
	"is_replicated",
	"is_non_sql_subscribed",
	"is_merge_published",
	"is_dts_replicated",
	"is_xml_document",
	"xml_collection_id",
	"default_object_id",
	"rule_object_id",
	"is_sparse",
	"is_column_set",
	"generated_always_type",
	"generated_always_type_desc",
	"encryption_type",
	"encryption_type_desc",
	"encryption_algorithm_name",
	"column_encryption_key_id",
	"column_encryption_key_database_name",
	"is_hidden",
	"is_masked",
	"graph_type",
	"graph_type_desc",
	"is_data_deletion_filter_column",
	"ledger_view_column_type",
	"ledger_view_column_type_desc",
	"is_dropped_ledger_column"
)

# Helper map of sys.columns column names to their index
[HashTable]$sysColumnsFieldIndexMap = @{}
For ([UInt16]$scfi = 0; $scfi -Lt $sysColumnsFields.Count; $scfi++) {
	$sysColumnsFieldIndexMap.Add($sysColumnsFields[$scfi].Trim().ToLower(), $scfi)
}

If (-Not (Test-Path -Path $sysColumnsContentsPath -PathType Leaf)) {
	ScriptFailure "No sys.columns output file found @ [$($sysColumnsContentsPath)]"
}

[string[]]$columnInfoRows = [System.IO.File]::ReadAllLines($sysColumnsContentsPath)
If ($columnInfoRows.Count -Eq 0) {
	ScriptFailure "No column infos found in [$($sysColumnsContentsPath)]"
}

[HashTable]$objectTypeMap = @{}

function processSysColumnRow() {
	[OutputType([System.Void])]
	Param(
		[string[]]$sysColumnsRow,
		[UInt16]$rowIndex)

	function isFieldValid() {
		[OutputType([bool])]
		Param([string]$fieldValue)
		return ((-Not [string]::IsNullOrEmpty($fieldValue)) -And $fieldValue -INe "NULL")
	}

	function appendTypeSpecifiers() {
		[OutputType([string])]
		Param([string]$type, [object[]]$specifiers, [string]$collationName)
		[string]$fullTypeName = $type
		[string[]]$validSpecifiers = $specifiers |
			Where-Object { isFieldValid -fieldValue $_ }
		If ($validSpecifiers.Count -Gt 0) {
			$fullTypeName = "$($fullTypeName)($($validSpecifiers -join ', '))"
		}
	
		If ($appendCollationName -And (isFieldValid $collationName)) {
			$fullTypeName = "$($fullTypeName) COLLATE $($collationName)"
		}
	
		return $fullTypeName
	}

	[string]$debugInfo = "Row #$($rowIndex)"
	If ($sysColumnsRow.Count -Ne $sysColumnsFields.Count) {
		Log Error "$($debugInfo): Invalid field count $($sysColumnsRow.Count) - $($sysColumnsFields.Count) expected"
		return
	}

	If ("system_type_id" -IEq $sysColumnsRow[$sysColumnsFieldIndexMap["system_type_id"]]) {
		Log Verbose "$($debugInfo): Skipping header row"
		return
	}

	[string]$objectId = $sysColumnsRow[$sysColumnsFieldIndexMap["object_id"]]
	If (-Not (isFieldValid $objectId)) {
		Log Error "$($debugInfo): Invalid object ID"
		return
	}

	[string]$columnName = $sysColumnsRow[$sysColumnsFieldIndexMap["name"]]
	If (-Not (isFieldValid $columnName)) {
		Log Error "$($debugInfo): Invalid column name"
		return
	}

	[UInt16]$columnIndex = [UInt16]$sysColumnsRow[$sysColumnsFieldIndexMap["column_id"]]
	If (-Not (isFieldValid $columnIndex)) {
		Log Error "$($debugInfo): Invalid column [$($columnName)] index"
		return
	}

	[UInt16]$systemTypeId = [UInt16]$sysColumnsRow[$sysColumnsFieldIndexMap["system_type_id"]]
	[UInt16]$userTypeId = [UInt16]$sysColumnsRow[$sysColumnsFieldIndexMap["user_type_id"]]
	[string]$maxLengthRaw = $sysColumnsRow[$sysColumnsFieldIndexMap["max_length"]]
	[string]$maxVLength = $Null
	[string]$maxNLength = $Null
	If (isFieldValid $maxLengthRaw) {
		[Int64]$maxLengthValue = [Int64]$maxLengthRaw
		If ($maxLengthValue -Lt 0) {
			$maxVLength = "MAX"
			$maxNLength = "MAX"
		} Else {
			$maxVLength = $maxLengthValue.ToString()
			# Unicode length will be the half of the Byte length
			$maxNLength = ($maxLengthValue / 2).ToString()
		}
	}

	[UInt16]$precision = $sysColumnsRow[$sysColumnsFieldIndexMap["precision"]]
	[UInt16]$scale = $sysColumnsRow[$sysColumnsFieldIndexMap["scale"]]
	[string]$collationName = $sysColumnsRow[$sysColumnsFieldIndexMap["collation_name"]]
	[string]$isNullableRaw = $sysColumnsRow[$sysColumnsFieldIndexMap["is_nullable"]]

	$debugInfo = "$($debugInfo), column #$($columnIndex)"
	[string[]]$additionalEntries = @(
		"Object ID: $($objectId)",
		"System type ID: $($systemTypeId)",
		"User type ID: $($userTypeId)",
		"Max length: $($maxLengthRaw)",
		"Precision: $($precision)",
		"Scale: $($scale)",
		"Collation: $($collationName)",
		"Is nullable: $($isNullableRaw)"
	)

	If ($systemTypeId -Ne $userTypeId) {
		Log Warning "$($debugInfo): Using system type ID $($systemTypeId) instead of user type ID $($userTypeId)"
	}

	# NOTE: Some types are not populated with type specifiers, default specifiers will be used instead
	# e.g. FLOAT will be explicitly used instead of FLOAT(25), where FLOAT(53) is the implicit default.
	[string]$systemTypeName = switch($systemTypeId) {
		34 { "IMAGE" }
		35 { appendTypeSpecifiers "TEXT" @($maxLength) }
		36 { "UNIQUEIDENTIFIER" }
		40 { "DATE" }
		41 { appendTypeSpecifiers "TIME" @($scale) }
		42 { appendTypeSpecifiers "DATETIME2" @($scale) }
		43 { appendTypeSpecifiers "DATETIMEOFFSET" @($scale) } 
		48 { "TINYINT" }
		52 { "SMALLINT" }
		56 { "INT" }
		58 { "SMALLDATETIME" }
		59 { "REAL" }
		60 { "MONEY" }
		61 { "DATETIME" }
		62 { "FLOAT" }
		98 { "SQL_VARIANT" }
		99 { appendTypeSpecifiers "NTEXT" @($maxNLength) }
		104 { "BIT" }
		106 { appendTypeSpecifiers "DECIMAL" @($precision, $scale) }
		108 { appendTypeSpecifiers "NUMERIC" @($precision, $scale) }
		122 { "SMALLMONEY" }
		127 { "BIGINT" }
		165 { appendTypeSpecifiers "VARBINARY" @($maxVLength) }
		167 { appendTypeSpecifiers "VARCHAR" @($maxVLength) $collationName }
		173 { appendTypeSpecifiers "BINARY" @($maxVLength) }
		175 { appendTypeSpecifiers "CHAR" @($maxVLength) $collationName }
		189 { "TIMESTAMP" }
		231 { appendTypeSpecifiers "NVARCHAR" @($maxNLength) $collationName }
		239 { appendTypeSpecifiers "NCHAR" @($maxNLength) $collationName }
		241 { "XML" }
		default { $Null}
	}

	If ([string]::IsNullOrEmpty($systemTypeName)) {
		Log Error "$($debugInfo): Invalid system type ID $($systemTypeId)" -additionalEntries $additionalEntries
		return
	}

	If (-Not $objectTypeMap.ContainsKey($objectId)) {
		$objectTypeMap.Add($objectId, @{ "columnTypeSchema" = [System.Collections.ArrayList]::new(); "columnTypeCounts" = [HashTable]@{} })
	}

	# Update column type counts for this object ID
	If ($objectTypeMap[$objectId].columnTypeCounts.ContainsKey($systemTypeName)) {
		$objectTypeMap[$objectId].columnTypeCounts[$systemTypeName]++
	} Else {
		$objectTypeMap[$objectId].columnTypeCounts.Add($systemTypeName, 1)
	}

	# Create a full column schema
	[string]$columnSchemaEntry = "[$($columnName)] $($systemTypeName)"
	If ($appendNullabilityOption -And (isFieldValid $isNullableRaw)) {
		If ($isNullableRaw -IEq "1" -Or $isNullableRaw -IEq "TRUE") {
			$columnSchemaEntry = "$($columnSchemaEntry) NULL"
		} Else {
			$columnSchemaEntry = "$($columnSchemaEntry) NOT NULL"
		}
	}

	If ($appendColumnIndex) {
		$columnSchemaEntry = "$($columnSchemaEntry) $($columnIndex)"
	}

	# Add the new column schema for this object ID
	$objectTypeMap[$objectId].columnTypeSchema.Add($columnSchemaEntry) | Out-Null

	Log Verbose "$($debugInfo): Schema name & type '$($columnSchemaEntry)'" -additionalEntries $additionalEntries
}

For ([UInt16]$cii = 0; $cii -Lt $columnInfoRows.Count; $cii++) {
	[string[]]$rowFields = $columnInfoRows[$cii] -split "," | ForEach-Object { $_.Trim() }
	processSysColumnRow $rowFields $cii
}

LogNewLine
If ($objectTypeMap.Keys.Count -Gt 0) {
	Log Info "Found column schemas for $($objectTypeMap.Keys.Count) object(s)"
} Else {
	ScriptFailure "Did not find any column schemas"
}

$objectTypeMap.Keys | Sort-Object | ForEach-Object {
	LogNewLine
	[HashTable]$columnCountMap = $objectTypeMap[$_].columnTypeCounts
	[string[]]$columnTypes = $objectTypeMap[$_].columnTypeSchema
	Log Info "Object ID $($_) with $($columnTypes.Count) column(s)"
	$columnCountMap.Keys | Sort-Object | ForEach-Object {
		Log Verbose "Found $($columnCountMap[$_].ToString().PadLeft(3, ' ')) x '$($_)'" -indentLevel 1
	}

	LogNewLine
	Log Success "Column type schema:" -additionalEntries $columnTypes -entryPrefix ", " -indentLevel 1
}

LogNewLine

#! /usr/bin/env tclsh

set hashInfo {
	sha1 {
		length 20
		command "openssl sha1"
	}
	sha256 {
		length 32
		command "openssl sha256"
	}
}

proc openssl {command filename} {
	catch {
		set output [exec openssl $command $filename]
	}

	if {![info exists output]} {
		return ""
	}

	set output [split $output =]
	set output [string trim [lindex $output end]]

	return $output
}

proc validationFailure {shortreason args} {
	puts "Content-type: text/plain"

	puts "Status: 400 $shortreason"

	puts ""

	foreach arg $args {
		puts "$arg"
	}

	exit 0
}

proc sendUserFile {filename} {
	if {[catch {
		set inFd [open $filename r]
	}]} {
		return false
	}

	fconfigure $inFd -translation binary

	puts "Content-type: application/octet-stream"
	puts ""

	flush stdout

	fconfigure stdout -translation binary

	fcopy $inFd stdout

	close $inFd

	return true
}

proc validateHash {filename command value} {
	lappend command $filename

	set chkValue [uplevel #0 $command]

	if {$chkValue == $value} {
		return true
	}

	return false
}

proc cacheRemoteURL {url cachefile hashCommand hashValue} {
	set retval false

	set tmpfile "${cachefile}-[expr rand()]"

	file mkdir [file dirname $tmpfile]

	catch {
		set outChan [open $tmpfile w]
	}

	if {![info exists outChan]} {
		return false
	}

	fconfigure $outChan -translation binary

	if {[catch {
		exec curl -sSkL $url >@ $outChan
	} err]} {
		set result "500"
		set resultString $err
	} else {
		set result "200"
		set resultString "Success"
	}

	close $outChan

	if {$result == 200} {
		if {[validateHash $tmpfile $hashCommand $hashValue]} {
			set retval true
			set reason "Success"

			file rename -force -- $tmpfile $cachefile
		} else {
			set reason "Hash validation failure"
		}
	} else {
		set reason "Fetching remote URL returned non-200: $result $resultString"
	}

	catch {
		file delete -force -- $tmpfile
	}

	return [list $retval $reason]
}

set baseDir $::env(DOCUMENT_ROOT)
set requestPath $::env(REQUEST_URI)

set work [split $requestPath /]
set hashMethod [lindex $work 1]
set hashValue [lindex $work 2]

set targetFile [file join $baseDir $hashMethod $hashValue]

if {![dict exists $hashInfo $hashMethod]} {
	validationFailure "Invalid Hashing Mechanism" \
		"Invalid hashing mechanism specified, must be one of: [join [dict keys $hashInfo] {, }]" \
		"Got: \"${hashMethod}\""
}

set hashLength [dict get $hashInfo $hashMethod length]
set hashCommand [dict get $hashInfo $hashMethod command]

if {[string length $hashValue] != [expr {$hashLength * 2}]} {
	validationFailure "Hash Value Specified" \
		"Invalid hash value specified -- wrong length.  The hash value supplied is expected to be a hex string of [expr {$hashLength * 2}] characters 0-9A-F" \
		"Got: \"${hashValue}\""
}

if {[file exists $targetFile]} {
	if {[sendUserFile $targetFile]} {
		exit 0
	}
}

if {![info exists ::env(HTTP_X_CACHE_URL)]} {
	validationFailure "Missing X-Cache-URL Header" \
		"No X-Cache-URL header found, we don't know what to cache and this hash does not already exist."
}

set originURL $::env(HTTP_X_CACHE_URL)

set cacheResult [cacheRemoteURL $originURL $targetFile $hashCommand $hashValue]
set cacheResultStatus [lindex $cacheResult 0]
set cacheResultReason [lindex $cacheResult 1]

if {$cacheResultStatus} {
	if {[sendUserFile $targetFile]} {
		exit 0
	}

	validationFailure "Failed open fetched file" \
		"We fetched the file, but we were not able to open afterwards.  Something has gone horribly wrong."
}

validationFailure "Failed to fetch remote file" \
	"We could not fetch the remote file: $cacheResultReason"

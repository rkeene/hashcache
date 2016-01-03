#! /usr/bin/env crystal

require "openssl"
require "openssl/digest"
require "http/client"
require "file.cr"

/*
 * Crystal 0.10 has a bug in the OpenSSL::Digest.update method, rewrite it here.
 */
module OpenSSL
  module DigestBase
    def update(io : IO)
      buffer :: UInt8[2048]
      while (read_bytes = io.read(buffer.to_slice)) > 0
        self << buffer.to_slice[0, read_bytes]
      end
      self
    end
  end
end

private def getHashInformation(hashMethod : String) : Hash
	begin
		hashData = OpenSSL::Digest.new(hashMethod)
	rescue
		raise "Unacceptable hashing algorithm: #{hashMethod}"
		
	end

	returnValue = {
		length: hashData.digest_size
	}

	return returnValue
end

private def validateFile(fileName, hashMethod, hashValue) : Bool
	checkHash = OpenSSL::Digest.new(hashMethod)

	checkHash.file(fileName)

	if checkHash.hexdigest === hashValue
		return true
	end

	return false
end

private def fetchFile(url : String, cacheFileName, hashMethod, hashValue)
	if (url =~ /^https?:\/\//).nil?
		raise "Invalid URL scheme\nWe only support HTTP, and HTTPS transports for origin URLs.  The URL must begin with one of: http://, https://"
	end

	tempFileName = "#{cacheFileName}-#{Random.rand}-#{Random.rand}-#{Random.rand}"

	Dir.mkdir_p(File.dirname(cacheFileName), mode = 0o755);

	HTTP::Client.get(url) { |result|
		if result.status_code != 200
			raise "Unable to fetch remote file, HTTP status code: #{result.status_code}"
		end

		if ! result.body_io?
			raise "Unable to fetch remote file, no body"
		end

		begin
			tempFile = File.open(tempFileName, "w");

			IO.copy(result.body_io, tempFile.to_fd_io);
		ensure
			if tempFile
				tempFile.close
			end
		end
	}

	if ! validateFile(tempFileName, hashMethod, hashValue)
		if File.exists?(tempFileName)
			File.delete(tempFileName)
		end

		raise "Unable to fetch remote file, validation failed"
	end

	File.rename(tempFileName, cacheFileName)
end

private def deliverFile(fileName)
	file = File.open(fileName)

	IO.copy(file, STDOUT)

	file.close
end

private def handleRequest(hashMethod, hashValue, upstreamURL = Nil)
	hashInfo = getHashInformation(hashMethod)

	if (hashValue.size != (hashInfo[:length] * 2))
		raise "Hash length is incorrect, it should be #{hashInfo[:length] * 2} hex digits long"
	end

	if (hashValue =~ /^[0-9a-f]*$/).nil?
		raise "Hash value is incorrect, it should contain only hex digits"
	end

	cacheFileName = hashMethod + "/" + hashValue

	if File.exists?(cacheFileName)
		return cacheFileName
	end

	if upstreamURL.is_a?(Nil)
		raise "Contents are not locally cached and no upstream URL has been provided"
	end

	fetchFile(upstreamURL, cacheFileName, hashMethod, hashValue)

	return cacheFileName
end

private def parseURL(url : String)
	urlParts = url.split("/")

	case urlParts.size
		when 1
			raise "No hash method or hash value specified."
		when 2
			raise "No hash value specified"
		when 3
			hashMethod = urlParts[1];
			hashValue = urlParts[2];
		else
			raise "Too many components specified in pathname"
	end

	return [hashMethod, hashValue]
end

private def createURL : String
	host = Nil

	["HTTP_HOST", "SERVER_NAME"].each { |hostEntry|
		if ENV[hostEntry]?
			host = ENV[hostEntry]

			break
		end
	}

	if host.is_a?(Nil)
		return "<unknown>"
	end

	if ENV["HTTPS"]? && ENV["HTTPS"] === "on"
		scheme = "https"
	else
		scheme = "http"
	end

	addPort = ""

	if ENV["SERVER_PORT"]?
		defaultPort = if scheme == "https"
			443
		else
			80
		end

		if  ENV["SERVER_PORT"].to_i != defaultPort
			addPort = ":#{ENV["SERVER_PORT"]}"
		end
	end

	return "#{scheme}://#{host}#{addPort}/"
end

private def cgiInterface
	if ENV["HTTP_X_CACHE_URL"]?
		upstreamURL = ENV["HTTP_X_CACHE_URL"]
	end

	begin
		hashMethod, hashValue = parseURL(ENV["REQUEST_URI"])

		outputFile = handleRequest(hashMethod, hashValue, upstreamURL)
	rescue reason
		puts "Status: 400 Not OK"
		puts "Content-type: text/plain"
		puts ""
		puts "Usage: #{createURL()}<hashMethod>/<hashValue>"
		puts "       Supply X-Cache-URL header with the origin URL to cache, it will be fetched and cached if the contents are not already available"
		puts ""
		puts "Example: curl --fail --header 'X-Cache-URL: http://www.rkeene.org/' http://hashcache.rkeene.org/sha1/dfc00e1a9ad78225527028db113d72c0ec8c12f8"
		puts ""
		puts "Error:"
		reason.to_s.split("\n").each { |line|
			puts "\t#{line}"
		}

		return
	end

	if outputFile.is_a?(String)
		if File.exists?(outputFile)
			puts "Status: 200 OK"
			puts "Content-type: application/octet-stream"
			puts ""
			deliverFile(outputFile)

			return
		end
	end

	puts "Status: 400 Not OK"
	puts "Content-type: text/plain"
	puts ""
	puts "Something went terribly wrong"
end

private def httpInterface
	puts "No HTTP interface yet"

	exit 1
end

if ENV["GATEWAY_INTERFACE"]?
	cgiInterface
else
	httpInterface
end

# Révoque les certificats de développement « Created via API » que
# `xcodebuild archive -allowProvisioningUpdates` crée à chaque passage de la
# CI (.github/workflows/ios.yml) : la clé privée meurt avec le runner, ils ne
# resserviraient jamais et s'accumuleraient. Le certificat de distribution
# n'est pas touché.
#
# Usage : ruby revoke_ci_certificates.rb (avec ASC_KEY_ID, ASC_ISSUER_ID et
# ASC_KEY_PATH dans l'environnement).
require 'base64'
require 'json'
require 'net/http'
require 'openssl'

def b64(data) = Base64.urlsafe_encode64(data, padding: false)

def token
  key = OpenSSL::PKey.read(File.read(ENV.fetch('ASC_KEY_PATH')))
  now = Time.now.to_i
  head = b64(JSON.dump(alg: 'ES256', kid: ENV.fetch('ASC_KEY_ID'), typ: 'JWT'))
  body = b64(JSON.dump(iss: ENV.fetch('ASC_ISSUER_ID'), iat: now, exp: now + 600,
                       aud: 'appstoreconnect-v1'))
  # Signature DER → r||s de 32 octets chacun (JWS ES256).
  der = key.sign(OpenSSL::Digest.new('SHA256'), "#{head}.#{body}")
  rs = OpenSSL::ASN1.decode(der).value.map { |i| i.value.to_s(2).rjust(32, "\0")[-32..] }
  "#{head}.#{body}.#{b64(rs.join)}"
end

def call(method, path, auth)
  uri = URI("https://api.appstoreconnect.apple.com#{path}")
  req = Net::HTTP.const_get(method).new(uri, 'Authorization' => "Bearer #{auth}")
  res = Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |http| http.request(req) }
  raise "#{method} #{path} : HTTP #{res.code} #{res.body}" unless res.is_a?(Net::HTTPSuccess)

  res.body.to_s.empty? ? {} : JSON.parse(res.body)
end

auth = token
certs = call('Get', '/v1/certificates?filter[certificateType]=DEVELOPMENT&limit=200', auth)['data']
ci = certs.select { |c| c.dig('attributes', 'name') == 'Apple Development: Created via API' }
ci.each do |c|
  call('Delete', "/v1/certificates/#{c['id']}", auth)
  puts "révoqué : #{c['id']} (expirait le #{c.dig('attributes', 'expirationDate')})"
end
puts 'aucun certificat de la CI à révoquer' if ci.empty?

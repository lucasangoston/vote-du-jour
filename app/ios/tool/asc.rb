# Client minimal de l'API App Store Connect, partagé par les scripts de la CI
# iOS (.github/workflows/ios.yml). Lit ASC_KEY_ID, ASC_ISSUER_ID et
# ASC_KEY_PATH (fichier .p8 de la clé API) dans l'environnement.
require 'base64'
require 'json'
require 'net/http'
require 'openssl'

module Asc
  module_function

  def b64(data) = Base64.urlsafe_encode64(data, padding: false)

  # Jeton JWT ES256 valable 20 minutes (maximum accepté par Apple).
  def token
    key = OpenSSL::PKey.read(File.read(ENV.fetch('ASC_KEY_PATH')))
    now = Time.now.to_i
    head = b64(JSON.dump(alg: 'ES256', kid: ENV.fetch('ASC_KEY_ID'), typ: 'JWT'))
    body = b64(JSON.dump(iss: ENV.fetch('ASC_ISSUER_ID'), iat: now, exp: now + 1200,
                         aud: 'appstoreconnect-v1'))
    # Signature DER → r||s de 32 octets chacun (JWS ES256).
    der = key.sign(OpenSSL::Digest.new('SHA256'), "#{head}.#{body}")
    rs = OpenSSL::ASN1.decode(der).value.map { |i| i.value.to_s(2).rjust(32, "\0")[-32..] }
    "#{head}.#{body}.#{b64(rs.join)}"
  end

  # Appel JSON:API ; renvoie le corps décodé ({} si vide), lève une erreur
  # avec la réponse d'Apple sinon. Le jeton est refait avant expiration.
  def call(method, path, body = nil)
    if @token.nil? || Time.now - @token_at > 900
      @token = token
      @token_at = Time.now
    end
    uri = URI("https://api.appstoreconnect.apple.com#{path}")
    req = Net::HTTP.const_get(method).new(uri, 'Authorization' => "Bearer #{@token}",
                                               'Content-Type' => 'application/json')
    req.body = JSON.dump(body) if body
    res = Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |http| http.request(req) }
    raise "#{method} #{path} : HTTP #{res.code} #{res.body}" unless res.is_a?(Net::HTTPSuccess)

    res.body.to_s.empty? ? {} : JSON.parse(res.body)
  end
end

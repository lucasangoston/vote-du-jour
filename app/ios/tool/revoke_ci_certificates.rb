# Révoque les certificats de développement « Created via API » que
# `xcodebuild archive -allowProvisioningUpdates` crée à chaque passage de la
# CI (.github/workflows/ios.yml) : la clé privée meurt avec le runner, ils ne
# resserviraient jamais et s'accumuleraient. Le certificat de distribution
# n'est pas touché.
#
# Usage : ruby revoke_ci_certificates.rb (environnement : voir asc.rb).
require_relative 'asc'

certs = Asc.call('Get', '/v1/certificates?filter[certificateType]=DEVELOPMENT&limit=200')['data']
ci = certs.select { |c| c.dig('attributes', 'name') == 'Apple Development: Created via API' }
ci.each do |c|
  Asc.call('Delete', "/v1/certificates/#{c['id']}")
  puts "révoqué : #{c['id']} (expirait le #{c.dig('attributes', 'expirationDate')})"
end
puts 'aucun certificat de la CI à révoquer' if ci.empty?

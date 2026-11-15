# Distribue un build envoyé par la CI aux testeurs externes (#129) : attend
# la fin du traitement par Apple, renseigne « À tester », ajoute le build au
# groupe externe (lien public) et le soumet à la review bêta.
#
# Usage : ruby distribute_testflight.rb <bundle id> <numéro de build> <À tester>
# (environnement : voir asc.rb ; groupe : TESTFLIGHT_GROUP, « Public » par
# défaut).
require_relative 'asc'

bundle_id, build_number, whats_new = ARGV
abort 'usage : distribute_testflight.rb <bundle id> <build> <À tester>' unless whats_new
group_name = ENV.fetch('TESTFLIGHT_GROUP', 'Public')

app = Asc.call('Get', "/v1/apps?filter[bundleId]=#{bundle_id}")['data'].first or abort "app #{bundle_id} introuvable"

# Le build n'apparaît dans l'API que quelques minutes après l'envoi, puis
# passe de PROCESSING à VALID (10 à 30 min au plus).
build = nil
deadline = Time.now + 40 * 60
loop do
  build = Asc.call('Get', "/v1/builds?filter[app]=#{app['id']}&filter[version]=#{build_number}")['data'].first
  state = build&.dig('attributes', 'processingState')
  puts "#{Time.now.strftime('%H:%M:%S')} build #{build_number} : #{state || 'pas encore visible'}"
  break if state == 'VALID'
  abort "build #{build_number} refusé par Apple : #{state}" if %w[FAILED INVALID].include?(state)
  abort "build #{build_number} toujours pas traité après 40 min" if Time.now > deadline

  sleep 30
end

# Apple crée souvent la localisation fr-FR du build lui-même : la modifier
# si elle existe, la créer sinon.
loc = Asc.call('Get', "/v1/builds/#{build['id']}/betaBuildLocalizations")['data']
         .find { |l| l.dig('attributes', 'locale') == 'fr-FR' }
if loc
  Asc.call('Patch', "/v1/betaBuildLocalizations/#{loc['id']}",
           { data: { type: 'betaBuildLocalizations', id: loc['id'], attributes: { whatsNew: whats_new } } })
else
  Asc.call('Post', '/v1/betaBuildLocalizations',
           { data: { type: 'betaBuildLocalizations',
                     attributes: { locale: 'fr-FR', whatsNew: whats_new },
                     relationships: { build: { data: { type: 'builds', id: build['id'] } } } } })
end
puts "À tester : #{whats_new}"

group = Asc.call('Get', "/v1/apps/#{app['id']}/betaGroups")['data']
           .find { |g| g.dig('attributes', 'name') == group_name } or abort "groupe #{group_name} introuvable"
Asc.call('Post', "/v1/betaGroups/#{group['id']}/relationships/builds",
         { data: [{ type: 'builds', id: build['id'] }] })
puts "ajouté au groupe #{group_name} : #{group.dig('attributes', 'publicLink')}"

begin
  submission = Asc.call('Post', '/v1/betaAppReviewSubmissions',
                        { data: { type: 'betaAppReviewSubmissions',
                                  relationships: { build: { data: { type: 'builds', id: build['id'] } } } } })
  puts "review bêta : #{submission.dig('data', 'attributes', 'betaReviewState')}"
rescue RuntimeError => e
  # Apple n'accepte qu'un build en review bêta à la fois : le build est dans
  # le groupe, il reste à le soumettre depuis TestFlight après la review en
  # cours. Avertissement visible dans le résumé du run, sans échec.
  raise unless e.message.include?('ANOTHER_BUILD_IN_REVIEW')

  puts "::warning::Build #{build_number} non soumis à la review bêta (#{e.message[0, 300]}). " \
       'Le soumettre depuis App Store Connect → TestFlight une fois la review en cours terminée.'
end

# Sièges réels : place de chaque député (AMO, placeHemicycle) + vote nominatif (Scrutins.json, numPlace).
import json, glob, sys, collections
GP = {}
for f in glob.glob('amo/x/json/organe/*.json'):
    o = json.load(open(f))['organe']
    if o.get('codeType') == 'GP' and not o['viMoDe'].get('dateFin'):
        GP[o['uid']] = o
ABBR = {'PO845401':'RN','PO845407':'EPR','PO845413':'LFI-NFP','PO845419':'SOC','PO845425':'DR','PO845439':'EcoS','PO845454':'Dem','PO845470':'HOR','PO845485':'LIOT','PO845514':'GDR','PO872880':'UDR','PO840056':'NI'}
deps = {}
for f in glob.glob('amo/x/json/acteur/*.json'):
    a = json.load(open(f))['acteur']
    uid = a['uid']['#text'] if isinstance(a['uid'], dict) else a['uid']
    ms = a['mandats']['mandat']; ms = ms if isinstance(ms, list) else [ms]
    place = grp = None
    for m in ms:
        if m.get('typeOrgane') == 'ASSEMBLEE' and m.get('legislature') == '17' and not m.get('dateFin'):
            mand = m.get('mandature') or {}
            place = mand.get('placeHemicycle')
        if m.get('typeOrgane') == 'GP' and not m.get('dateFin'):
            grp = m['organes']['organeRef']
    if place: deps[uid] = {'place': int(place), 'g': ABBR.get(grp, grp)}
print('députés avec place', len(deps), file=sys.stderr)
out = {}
for num in (8706, 8610):
    s = json.load(open(f'scr/json/VTANR5L17V{num}.json'))['scrutin']
    seats = {}  # place -> record
    for d in deps.values(): seats[d['place']] = {'place': d['place'], 'g': d['g'], 'v': 'absent'}
    sizes = {}; tally = collections.Counter()
    for g in s['ventilationVotes']['organe']['groupes']['groupe']:
        ab = ABBR[g['organeRef']]; sizes[ab] = int(g['nombreMembresGroupe'])
        nom = g['vote']['decompteNominatif']
        for key, v in (('pours','pour'),('contres','contre'),('abstentions','abst'),('nonVotants','nv')):
            blk = nom.get(key)
            if not blk: continue
            vs = blk['votant']; vs = vs if isinstance(vs, list) else [vs]
            for x in vs:
                p = int(x['numPlace']) if x.get('numPlace') else deps.get(x['acteurRef'], {}).get('place')
                tally[v] += 1
                if p is None: print('sans place', num, x, file=sys.stderr); continue
                seats.setdefault(p, {'place': p, 'g': ab, 'v': 'absent'})
                seats[p]['v'] = v; seats[p]['g'] = ab
    out[num] = {'sizes': sizes, 'tally': dict(tally), 'seats': sorted(seats.values(), key=lambda r: r['place'])}
    print(num, 'sièges', len(seats), 'tally', dict(tally), file=sys.stderr)
json.dump(out, open('data/seats.json', 'w'))

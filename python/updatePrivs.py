import json
ps = json.load(open('./work/db/privilegeExport.json'))
rs = json.load(open('./work/db/roleExport.json'))
privIds = []
for p in ps:
    privIds.append(p['id'])

for i, r in enumerate(rs):
    for _p in r['privileges']:
        if _p not in privIds:
            rs[i]['privileges'].remove(_p)

with open('./roleExportMod.json', 'w') as f:
    json.dump(rs, f)
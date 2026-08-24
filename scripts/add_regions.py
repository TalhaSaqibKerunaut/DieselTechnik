import os, re, sys

REGION_MAP = {
    "01": "Auvergne-Rh\u00f4ne-Alpes",
    "02": "Hauts-de-France",
    "03": "Auvergne-Rh\u00f4ne-Alpes",
    "04": "Provence-Alpes-C\u00f4te d\u2019Azur",
    "05": "Provence-Alpes-C\u00f4te d\u2019Azur",
    "06": "Provence-Alpes-C\u00f4te d\u2019Azur",
    "07": "Auvergne-Rh\u00f4ne-Alpes",
    "08": "Grand Est",
    "09": "Occitanie",
    "10": "Grand Est",
    "11": "Occitanie",
    "12": "Occitanie",
    "13": "Provence-Alpes-C\u00f4te d\u2019Azur",
    "14": "Normandie",
    "15": "Auvergne-Rh\u00f4ne-Alpes",
    "16": "Nouvelle-Aquitaine",
    "17": "Nouvelle-Aquitaine",
    "18": "Centre-Val de Loire",
    "19": "Nouvelle-Aquitaine",
    "21": "Bourgogne-Franche-Comt\u00e9",
    "22": "Bretagne",
    "23": "Nouvelle-Aquitaine",
    "24": "Nouvelle-Aquitaine",
    "25": "Bourgogne-Franche-Comt\u00e9",
    "26": "Auvergne-Rh\u00f4ne-Alpes",
    "27": "Normandie",
    "28": "Centre-Val de Loire",
    "29": "Bretagne",
    "2A": "Corse",
    "2B": "Corse",
    "30": "Occitanie",
    "31": "Occitanie",
    "32": "Occitanie",
    "33": "Nouvelle-Aquitaine",
    "34": "Occitanie",
    "35": "Bretagne",
    "36": "Centre-Val de Loire",
    "37": "Centre-Val de Loire",
    "38": "Auvergne-Rh\u00f4ne-Alpes",
    "39": "Bourgogne-Franche-Comt\u00e9",
    "40": "Nouvelle-Aquitaine",
    "41": "Centre-Val de Loire",
    "42": "Auvergne-Rh\u00f4ne-Alpes",
    "43": "Auvergne-Rh\u00f4ne-Alpes",
    "44": "Pays de la Loire",
    "45": "Centre-Val de Loire",
    "46": "Occitanie",
    "47": "Nouvelle-Aquitaine",
    "48": "Occitanie",
    "49": "Pays de la Loire",
    "50": "Normandie",
    "51": "Grand Est",
    "52": "Grand Est",
    "53": "Pays de la Loire",
    "54": "Grand Est",
    "55": "Grand Est",
    "56": "Bretagne",
    "57": "Grand Est",
    "58": "Bourgogne-Franche-Comt\u00e9",
    "59": "Hauts-de-France",
    "60": "Hauts-de-France",
    "61": "Normandie",
    "62": "Hauts-de-France",
    "63": "Auvergne-Rh\u00f4ne-Alpes",
    "64": "Nouvelle-Aquitaine",
    "65": "Occitanie",
    "66": "Occitanie",
    "67": "Grand Est",
    "68": "Grand Est",
    "69": "Auvergne-Rh\u00f4ne-Alpes",
    "70": "Bourgogne-Franche-Comt\u00e9",
    "71": "Bourgogne-Franche-Comt\u00e9",
    "72": "Pays de la Loire",
    "73": "Auvergne-Rh\u00f4ne-Alpes",
    "74": "Auvergne-Rh\u00f4ne-Alpes",
    "75": "\u00cele-de-France",
    "76": "Normandie",
    "77": "\u00cele-de-France",
    "78": "\u00cele-de-France",
    "79": "Nouvelle-Aquitaine",
    "80": "Hauts-de-France",
    "81": "Occitanie",
    "82": "Occitanie",
    "83": "Provence-Alpes-C\u00f4te d\u2019Azur",
    "84": "Provence-Alpes-C\u00f4te d\u2019Azur",
    "85": "Pays de la Loire",
    "86": "Nouvelle-Aquitaine",
    "87": "Nouvelle-Aquitaine",
    "88": "Grand Est",
    "89": "Bourgogne-Franche-Comt\u00e9",
    "90": "Bourgogne-Franche-Comt\u00e9",
    "91": "\u00cele-de-France",
    "92": "\u00cele-de-France",
    "93": "\u00cele-de-France",
    "94": "\u00cele-de-France",
    "95": "\u00cele-de-France",
    "971": "Guadeloupe",
    "972": "Martinique",
    "973": "Guyane",
    "974": "La R\u00e9union",
    "976": "Mayotte",
}

MDT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "force-app/main/default/customMetadata")

REGION_BLOCK = (
    '    <values>\n'
    '        <field>KS_Region__c</field>\n'
    '        <value xsi:type="xsd:string">{region}</value>\n'
    '    </values>\n'
    '</CustomMetadata>'
)

updated = 0
skipped = 0
errors = []

for filename in sorted(os.listdir(MDT_DIR)):
    if not filename.startswith("KS_PostalCodeStateMap.FR"):
        continue
    filepath = os.path.join(MDT_DIR, filename)
    with open(filepath, "r", encoding="utf-8") as f:
        content = f.read()
    match = re.search(r'<field>KS_StateCode__c</field>\s*<value[^>]*>([^<]+)</value>', content)
    if not match:
        errors.append(f"  SKIP (no state code): {filename}")
        skipped += 1
        continue
    state_code = match.group(1).strip()
    region = REGION_MAP.get(state_code)
    if not region:
        errors.append(f"  SKIP (no region for '{state_code}'): {filename}")
        skipped += 1
        continue
    if "KS_Region__c" in content:
        skipped += 1
        continue
    new_content = content.replace("</CustomMetadata>", REGION_BLOCK.format(region=region))
    with open(filepath, "w", encoding="utf-8") as f:
        f.write(new_content)
    updated += 1

for e in errors:
    print(e, file=sys.stderr)
print(f"Done. Updated: {updated}, Skipped: {skipped}")

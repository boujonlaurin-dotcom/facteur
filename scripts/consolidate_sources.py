"""
Script to consolidate sources.csv and sources_candidates.csv into sources_master.csv.
Implements the 3-state logic:
- CURATED: If in sources.csv OR (in candidates with In_Catalog=true)
- INDEXED: If in candidates and NOT Curated
- ARCHIVED: Not used yet (default for others if logic changes)
"""

import csv
import os

# New Rationales for the 6 sources requested by user
NEW_RATIONALES = {
    "France Info": "Service public d'information. Référence fiable et vérifiée. Indépendance statutaire forte, mission de neutralité. Site accessible, sans mur payant, priorité au factuel et à l'immédiateté.",
    "France Inter": "Première radio de France (Service Public). Excellente qualité éditoriale, programmation riche. Indépendance éditoriale respectée. Accessibilité audio et numérique exemplaire.",
    "RTL": "Radio généraliste privée (Groupe M6). Information grand public professionnelle. Modèle commercial dépendant de la publicité. Ligne éditoriale consensuelle.",
    "Europe 1": "Radio privée (Groupe Lagardère/Vivendi). Virage éditorial marqué vers l'opinion sous l'influence de l'actionnaire. Qualité technique présente mais indépendance éditoriale questionnée.",
    "Brut": "Média vidéo 'Social First'. Propriété de CMA Media (Rodolphe Saadé) depuis 2025. Formats courts et engageants. Accessible (Mobile-first), mais indépendance capitalistique à surveiller.",
    "Blast": "Web TV indépendante et engagée (SCIC). Financement par le public garantissant l'indépendance capitalistique. Ligne éditoriale militante et investigations parfois controversées."
}

# New Scores (Independence, Rigor, UX) for the 6 sources
# Scale 0.0 to 1.0
NEW_SCORES = {
    "France Info":  {"indep": 0.9, "rigor": 0.9, "ux": 0.9},
    "France Inter": {"indep": 0.9, "rigor": 0.9, "ux": 1.0},
    "RTL":          {"indep": 0.6, "rigor": 0.7, "ux": 0.7},
    "Europe 1":     {"indep": 0.4, "rigor": 0.6, "ux": 0.7},
    "Brut":         {"indep": 0.5, "rigor": 0.6, "ux": 0.9},
    "Blast":        {"indep": 1.0, "rigor": 0.7, "ux": 0.6}
}

def consolidate():
    root_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    sources_path = os.path.join(root_dir, "sources", "sources.csv")
    candidates_path = os.path.join(root_dir, "sources", "sources_candidates.csv")
    master_path = os.path.join(root_dir, "sources", "sources_master.csv")

    print(f"Starting consolidation... Sources: {sources_path}, Candidates: {candidates_path}")
    
    unified_sources = {}
    
    # helper to normalize url
    def norm_url(u):
        if not u: return ""
        return u.strip().rstrip('/')

    # 1. Read existing curated sources (Highest priority)
    if os.path.exists(sources_path):
        print("Reading existing sources...")
        with open(sources_path, 'r', encoding='utf-8') as f:
            reader = csv.DictReader(f)
            for row in reader:
                url = norm_url(row.get('URL'))
                name = row.get('Name')
                key = url if url else name
                
                # Default scores if missing
                scores = {"indep": None, "rigor": None, "ux": None}
                # Check if we have specific updates for this key
                if name in NEW_SCORES:
                    scores = NEW_SCORES[name]
                
                entry = {
                    "Name": name,
                    "URL": row.get('URL'),
                    "Type": row.get('Type'),
                    "Thème": row.get('Thème'),
                    "Rationale": NEW_RATIONALES.get(name, row.get('Rationale')), # Use new rationale if available
                    "Status": "CURATED",
                    "Bias": row.get('Bias'),
                    "Reliability": row.get('Reliability'),
                    "Score_Independence": scores['indep'],
                    "Score_Rigor": scores['rigor'],
                    "Score_UX": scores['ux']
                }
                unified_sources[key] = entry

    # 2. Read candidates
    if os.path.exists(candidates_path):
        with open(candidates_path, 'r', encoding='utf-8') as f:
            reader = csv.DictReader(f)
            for row in reader:
                url = norm_url(row.get('URL'))
                name = row.get('Name')
                
                if not name or name == "Name": continue

                key = url if url else name
                
                # Check In_Catalog flag
                in_catalog = row.get("In_Catalog", "false").lower() == "true"
                status = "CURATED" if in_catalog else "INDEXED"
                
                # Get updated rationale/scores if match
                rationale = NEW_RATIONALES.get(name, row.get('Rationale'))
                scores = NEW_SCORES.get(name, {"indep": None, "rigor": None, "ux": None})
                
                if key in unified_sources:
                    # Already exists from sources.csv, let's update missing fields or status if strictly superior
                    # But sources.csv is already CURATED, so we mostly just check if we have better metadata
                    # Actually, for the 6 new sources, they are in candidates but might not be in sources.csv yet?
                    # Or they might have been added to candidates with In_Catalog=True.
                    # We prioritize the NEW_RATIONALES if provided.
                    if name in NEW_SCORES:
                         unified_sources[key]["Score_Independence"] = scores['indep']
                         unified_sources[key]["Score_Rigor"] = scores['rigor']
                         unified_sources[key]["Score_UX"] = scores['ux']
                         unified_sources[key]["Rationale"] = rationale
                else:
                    # New entry
                    # Map heuristic scores if needed for INDEXED ? 
                    # The prompt asked to clarify validation. 
                    # For INDEXED, we don't need scores.
                    # For CURATED, we need scores.
                    
                    if status == "CURATED" and not scores['indep']:
                        # If it is curated but not in our NEW_SCORES map, we might need default values?
                        # Or maybe we leverage the "Reliability" to heuristic map like in import_sources.py
                        pass

                    entry = {
                        "Name": name,
                        "URL": row.get('URL'),
                        "Type": row.get('Type'),
                        "Thème": row.get('Thème'),
                        "Rationale": rationale,
                        "Status": status,
                        "Bias": row.get('Bias'),
                        "Reliability": row.get('Reliability'),
                        "Score_Independence": scores['indep'],
                        "Score_Rigor": scores['rigor'],
                        "Score_UX": scores['ux']
                    }
                    unified_sources[key] = entry

    # 3. Write Master CSV
    fieldnames = ["Name", "URL", "Type", "Thème", "Status", "Rationale", "Bias", "Reliability", "Score_Independence", "Score_Rigor", "Score_UX"]
    
    with open(master_path, 'w', encoding='utf-8') as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        
        # Sort by status (CURATED first) then Name
        sorted_items = sorted(unified_sources.values(), key=lambda x: (0 if x['Status']=='CURATED' else 1, x['Name']))
        
        for item in sorted_items:
            writer.writerow({k: item.get(k) for k in fieldnames})
            
    print(f"✅ Generated {master_path}")
    print(f"Total entries: {len(unified_sources)}")
    print(f"CURATED: {len([x for x in unified_sources.values() if x['Status']=='CURATED'])}")
    print(f"INDEXED: {len([x for x in unified_sources.values() if x['Status']=='INDEXED'])}")

if __name__ == "__main__":
    consolidate()

# =============================================================================
# AMIIN LEGAL — SUITE DE TESTS
# Fichier  : test_amiin_legal.py
# Exécuter : python.exe -m pytest test_amiin_legal.py -v
# Couvre   : prescription (la fonction la plus critique), extraction lettre
#            client, résumé exécutif, calendrier ICS, chiffrement.
# =============================================================================

from datetime import datetime, timedelta

import pytest

from amiin_legal_prompts import (
    PRESCRIPTIONS,
    TYPES_AFFAIRES,
    calculer_alerte_prescription,
)


def date_il_y_a(jours: int) -> str:
    return (datetime.now() - timedelta(days=jours)).strftime("%Y-%m-%d")


# =============================================================================
# 1. PRESCRIPTION — la fonction la plus critique du produit
# =============================================================================

class TestPrescription:

    def test_licenciement_recent_est_vert(self):
        r = calculer_alerte_prescription("licenciement_abusif", date_il_y_a(30))
        assert r["niveau_alerte"] == "vert"
        assert r["jours_restants"] > 900

    def test_licenciement_proche_expiration_est_rouge(self):
        # 3 ans - 30 jours → alerte_rouge (seuil 90 j)
        r = calculer_alerte_prescription("licenciement_abusif", date_il_y_a(3 * 365 - 30))
        assert r["niveau_alerte"] == "rouge"
        assert 0 < r["jours_restants"] <= 90

    def test_licenciement_expire(self):
        r = calculer_alerte_prescription("licenciement_abusif", date_il_y_a(3 * 365 + 10))
        assert r["niveau_alerte"] == "expiree"
        assert r["jours_restants"] <= 0

    def test_zone_orange(self):
        # 3 ans - 150 jours → entre rouge (90) et orange (180)
        r = calculer_alerte_prescription("licenciement_abusif", date_il_y_a(3 * 365 - 150))
        assert r["niveau_alerte"] == "orange"

    # ── Pénal délit / crime (correction v2.1) ────────────────────────────────

    def test_penal_delit_3_ans(self):
        r = calculer_alerte_prescription("penal_delit", date_il_y_a(2 * 365))
        assert r["niveau_alerte"] in ("vert", "orange")
        assert r["jours_restants"] <= 365 + 5

    def test_penal_crime_10_ans_pas_expire_apres_4_ans(self):
        """Bug v2.0 corrigé : un crime après 4 ans NE doit PAS être expiré."""
        r = calculer_alerte_prescription("penal_crime", date_il_y_a(4 * 365))
        assert r["niveau_alerte"] != "expiree"
        assert r["jours_restants"] > 5 * 365

    def test_penal_crime_expire_apres_11_ans(self):
        r = calculer_alerte_prescription("penal_crime", date_il_y_a(11 * 365))
        assert r["niveau_alerte"] == "expiree"

    def test_penal_defense_alias_retrocompatible(self):
        """L'ancien code 'penal_defense' doit toujours fonctionner (délai délit)."""
        r = calculer_alerte_prescription("penal_defense", date_il_y_a(100))
        assert r["niveau_alerte"] in ("vert", "orange", "rouge")
        assert r["jours_restants"] is not None

    # ── Cas limites ───────────────────────────────────────────────────────────

    def test_divorce_sans_prescription_est_info(self):
        r = calculer_alerte_prescription("divorce", date_il_y_a(1000))
        assert r["niveau_alerte"] == "info"
        assert r["jours_restants"] is None

    def test_date_invalide_retourne_info_sans_crash(self):
        r = calculer_alerte_prescription("licenciement_abusif", "pas-une-date")
        assert r["niveau_alerte"] == "info"
        assert r["jours_restants"] is None

    def test_date_none_sans_crash(self):
        r = calculer_alerte_prescription("licenciement_abusif", None)
        assert r["niveau_alerte"] == "info"

    def test_type_inconnu_fallback_autre(self):
        r = calculer_alerte_prescription("type_qui_nexiste_pas", date_il_y_a(10))
        assert r["niveau_alerte"] == "info"

    def test_refere_urgence_rouge_immediatement(self):
        r = calculer_alerte_prescription("refere_urgence", date_il_y_a(1))
        assert r["niveau_alerte"] in ("rouge", "expiree")

    def test_contentieux_administratif_2_mois(self):
        r = calculer_alerte_prescription("contentieux_administratif", date_il_y_a(70))
        assert r["niveau_alerte"] == "expiree"

    # ── Cohérence des tables ──────────────────────────────────────────────────

    def test_tous_les_types_affaires_ont_une_prescription(self):
        for code in TYPES_AFFAIRES:
            presc = PRESCRIPTIONS.get(code, PRESCRIPTIONS.get("autre"))
            assert presc is not None, f"Type {code} sans entrée prescription ni fallback"

    def test_aucune_reference_code_civil_francais(self):
        """Vérifie qu'aucun placeholder de droit français ne reste (Art. 2224 etc.)."""
        for code, presc in PRESCRIPTIONS.items():
            article = presc["article"]
            if "2224" in article:
                assert "à confirmer" in article.lower() or "français" in article.lower(), \
                    f"{code} : référence française non signalée comme à confirmer"

    def test_message_contient_date_limite_si_delai(self):
        r = calculer_alerte_prescription("recouvrement_creance", date_il_y_a(100))
        assert r["date_limite"] is not None
        assert r["date_limite"] in r["message"]


# =============================================================================
# 2. EXTRACTION LETTRE CLIENT
# =============================================================================

from amiin_legal_api import (
    _construire_ics,
    _extraire_evenements_calendrier,
    _extraire_lettre_client,
    _extraire_resume_executif,
)


DOSSIER_EXEMPLE = """# DOSSIER AMIIN LEGAL
## Contentieux du Travail — Ahmed

## SECTION 1 — RÉSUMÉ EXÉCUTIF
Le client a été licencié sans procédure ni indemnités après 8 ans d'ancienneté.
La position juridique est forte. Action prioritaire : saisine du Tribunal du Travail.

---

## SECTION 7 — LETTRE DE SYNTHÈSE POUR LE CLIENT

<!-- DEBUT_LETTRE_CLIENT -->

⚠️ À RELIRE ET SIGNER PAR L'AVOCAT RESPONSABLE AVANT ENVOI AU CLIENT ⚠️

---

Djibouti, le 10/06/2026

Madame, Monsieur Ahmed,

Votre licenciement nous paraît contestable.

Cordialement,

Maître X

<!-- FIN_LETTRE_CLIENT -->

---

## SECTION 8 — CALENDRIER PROCÉDURAL

| Étape | Action | Date limite | Responsable | Statut |
|-------|--------|-------------|-------------|--------|
| 1 | Mise en demeure | 20/06/2026 | Avocat | ⬜ À faire |
| 2 | Dépôt requête | 15/07/2026 | Avocat | ⬜ À faire |

## SECTION 9 — DOCUMENTS
"""


class TestExtractionLettre:

    def test_extraction_normale(self):
        lettre = _extraire_lettre_client(DOSSIER_EXEMPLE)
        assert "Madame, Monsieur Ahmed" in lettre
        assert "Cordialement" in lettre

    def test_avertissement_interne_supprime(self):
        lettre = _extraire_lettre_client(DOSSIER_EXEMPLE)
        assert "À RELIRE ET SIGNER" not in lettre

    def test_marqueurs_supprimes(self):
        lettre = _extraire_lettre_client(DOSSIER_EXEMPLE)
        assert "DEBUT_LETTRE_CLIENT" not in lettre
        assert "FIN_LETTRE_CLIENT" not in lettre

    def test_marqueurs_absents_fallback(self):
        lettre = _extraire_lettre_client("# Dossier sans lettre")
        assert "n'a pas pu être extraite" in lettre

    def test_separateur_apres_avertissement_supprime(self):
        lettre = _extraire_lettre_client(DOSSIER_EXEMPLE)
        # Le --- qui suit immédiatement l'avertissement doit disparaître,
        # la lettre ne doit pas commencer par un séparateur
        assert not lettre.startswith("---")


class TestResumeExecutif:

    def test_extrait_section_1(self):
        resume = _extraire_resume_executif(DOSSIER_EXEMPLE)
        assert "licencié" in resume
        assert len(resume) <= 300

    def test_ignore_titres(self):
        resume = _extraire_resume_executif(DOSSIER_EXEMPLE)
        assert not resume.startswith("#")

    def test_fallback_sans_section(self):
        resume = _extraire_resume_executif("Texte brut sans section ni titre.")
        assert "Texte brut" in resume

    def test_document_vide(self):
        resume = _extraire_resume_executif("")
        assert resume == "Résumé non disponible."


# =============================================================================
# 3. CALENDRIER ICS
# =============================================================================

class TestCalendrierICS:

    def test_extraction_evenements(self):
        evs = _extraire_evenements_calendrier(DOSSIER_EXEMPLE, "Ahmed")
        assert len(evs) == 2
        dates = [e["date"].strftime("%d/%m/%Y") for e in evs]
        assert "20/06/2026" in dates
        assert "15/07/2026" in dates

    def test_actions_extraites(self):
        evs = _extraire_evenements_calendrier(DOSSIER_EXEMPLE, "Ahmed")
        actions = [e["action"] for e in evs]
        assert any("demeure" in a for a in actions)

    def test_ics_valide(self):
        evs = _extraire_evenements_calendrier(DOSSIER_EXEMPLE, "Ahmed")
        ics = _construire_ics(evs, "TEST1234", "Ahmed c/ Employeur")
        assert ics.startswith("BEGIN:VCALENDAR")
        assert ics.endswith("END:VCALENDAR")
        assert ics.count("BEGIN:VEVENT") == 2
        assert "DTSTART;VALUE=DATE:20260620" in ics
        assert "VALARM" in ics  # rappel J-7

    def test_dossier_sans_calendrier(self):
        evs = _extraire_evenements_calendrier("# Dossier\nPas de section 8.", "X")
        assert evs == []


# =============================================================================
# 4. CHIFFREMENT (si cryptography installé)
# =============================================================================

class TestChiffrement:

    def test_roundtrip_si_active(self):
        import amiin_legal_api as api
        if api._fernet is None:
            pytest.skip("Chiffrement non activé (AMIIN_ENCRYPT_KEY absente)")
        texte = "Données client confidentielles — M. Ahmed, Djibouti"
        chiffre = api._chiffrer(texte)
        assert chiffre != texte
        assert chiffre.startswith("enc::")
        assert api._dechiffrer(chiffre) == texte

    def test_dechiffrer_texte_clair_inchange(self):
        import amiin_legal_api as api
        assert api._dechiffrer("texte en clair") == "texte en clair"
        assert api._dechiffrer(None) is None

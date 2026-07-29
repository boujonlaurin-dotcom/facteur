/* Facteur Landing Page — Consentement cookies (Google Consent Mode v2)
 *
 * Source unique pour le stub gtag/dataLayer, le bandeau de consentement et
 * le chargement de GA4. Chargé sur chaque page via un seul <script> — pas de
 * markup ni de stub dupliqués par page (risque de drift entre 11 copies).
 */
(function () {
    'use strict';

    var STORAGE_KEY = 'ga_consent_choice';
    var GA_MEASUREMENT_ID = 'G-LJ2QT4846J';

    window.dataLayer = window.dataLayer || [];
    function gtag() { dataLayer.push(arguments); }
    window.gtag = gtag;

    gtag('consent', 'default', {
        analytics_storage: 'denied',
        ad_storage: 'denied',
        ad_user_data: 'denied',
        ad_personalization: 'denied'
    });

    var gaLoaded = false;

    function loadGA() {
        if (gaLoaded) return;
        gaLoaded = true;
        gtag('consent', 'update', { analytics_storage: 'granted' });
        var script = document.createElement('script');
        script.async = true;
        script.src = 'https://www.googletagmanager.com/gtag/js?id=' + GA_MEASUREMENT_ID;
        document.head.appendChild(script);
        gtag('js', new Date());
        gtag('config', GA_MEASUREMENT_ID, { anonymize_ip: true });
    }

    var stored = null;
    try {
        stored = window.localStorage.getItem(STORAGE_KEY);
    } catch (e) {
        stored = null;
    }

    if (stored === 'granted') {
        loadGA();
        return;
    }
    if (stored === 'denied') {
        return;
    }

    function renderBanner() {
        var link = document.createElement('link');
        link.rel = 'stylesheet';
        link.href = '/css/consent.css?v=1';
        document.head.appendChild(link);

        var banner = document.createElement('div');
        banner.id = 'consent-banner';
        banner.innerHTML =
            '<p>Nous utilisons Google Analytics pour mesurer l’audience du site. ' +
            'Ces cookies ne sont déposés qu’avec ton accord. ' +
            '<a href="/politique-confidentialite.html">En savoir plus</a></p>' +
            '<div class="consent-banner__actions">' +
            '<button type="button" id="consent-refuse">Refuser</button>' +
            '<button type="button" id="consent-accept">Accepter</button>' +
            '</div>';
        document.body.appendChild(banner);

        function choose(choice) {
            try {
                window.localStorage.setItem(STORAGE_KEY, choice);
            } catch (e) {
                // localStorage indisponible (navigation privée) : le choix ne sera pas persisté,
                // le bandeau réapparaîtra au prochain chargement.
            }
            if (choice === 'granted') loadGA();
            banner.remove();
        }

        document.getElementById('consent-accept').addEventListener('click', function () { choose('granted'); });
        document.getElementById('consent-refuse').addEventListener('click', function () { choose('denied'); });
    }

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', renderBanner);
    } else {
        renderBanner();
    }
})();

/* Facteur Landing Page */

(function () {
    'use strict';

    var API_URL = 'https://facteur-production.up.railway.app';

    // ── UTM Capture ─────────────────────────────
    var urlParams = new URLSearchParams(window.location.search);
    var utmData = {
        utm_source: urlParams.get('utm_source') || null,
        utm_medium: urlParams.get('utm_medium') || null,
        utm_campaign: urlParams.get('utm_campaign') || null,
    };

    // ── Scroll Reveal ─────────────────────────────
    var observer = new IntersectionObserver(
        function (entries) {
            entries.forEach(function (entry) {
                if (entry.isIntersecting) {
                    entry.target.classList.add('visible');
                }
            });
        },
        { threshold: 0.15 }
    );

    document.querySelectorAll('.reveal').forEach(function (el) {
        observer.observe(el);
    });

    // ── Testimonial card paper entrance stagger ──
    document.querySelectorAll('.testimonial-card').forEach(function (card, i) {
        card.style.transitionDelay = (i * 120) + 'ms';
    });

    // ── Survey Modal ────────────────────────────
    var surveyModal = document.getElementById('survey-modal');
    var surveyForm = document.getElementById('survey-form');
    var surveyContent = document.getElementById('survey-content');
    var surveyDone = document.getElementById('survey-done');
    var surveyClose = surveyModal.querySelector('.survey-close');
    var lastSignupEmail = '';

    function openSurvey(email) {
        lastSignupEmail = email;
        surveyContent.hidden = false;
        surveyDone.hidden = true;
        surveyForm.reset();
        surveyForm.querySelectorAll('.survey-option.is-checked').forEach(function (el) {
            el.classList.remove('is-checked');
        });
        painOrder = [];
        document.querySelectorAll('.pain-item').forEach(function (item) {
            item.classList.remove('selected');
            item.querySelector('.pain-rank').textContent = '';
        });
        surveyModal.style.display = 'flex';
        surveyModal.classList.add('is-open');
        document.body.style.overflow = 'hidden';
    }

    function closeSurvey() {
        surveyModal.classList.remove('is-open');
        surveyModal.style.display = 'none';
        document.body.style.overflow = '';
    }

    surveyClose.addEventListener('click', closeSurvey);
    surveyModal.addEventListener('click', function (e) {
        if (e.target === surveyModal) closeSurvey();
    });

    // ── Radio highlight (Q1/Q3) ─────────────────
    surveyForm.querySelectorAll('input[type="radio"]').forEach(function (radio) {
        radio.addEventListener('change', function () {
            var name = radio.getAttribute('name');
            surveyForm.querySelectorAll('input[name="' + name + '"]').forEach(function (r) {
                r.closest('.survey-option').classList.remove('is-checked');
            });
            radio.closest('.survey-option').classList.add('is-checked');
        });
    });

    // ── Pain Ranking (Q2) ───────────────────────
    var painOrder = [];
    var painItems = document.querySelectorAll('.pain-item');

    painItems.forEach(function (item) {
        item.addEventListener('click', function () {
            var value = item.getAttribute('data-value');
            var idx = painOrder.indexOf(value);

            if (idx !== -1) {
                // Deselect: remove and renumber
                painOrder.splice(idx, 1);
                item.classList.remove('selected');
                item.querySelector('.pain-rank').textContent = '';
                // Renumber remaining
                painItems.forEach(function (el) {
                    var pos = painOrder.indexOf(el.getAttribute('data-value'));
                    if (pos !== -1) {
                        el.querySelector('.pain-rank').textContent = (pos + 1);
                    }
                });
            } else {
                // Select
                painOrder.push(value);
                item.classList.add('selected');
                item.querySelector('.pain-rank').textContent = painOrder.length;
            }
        });
    });

    // ── Survey Submit ───────────────────────────
    surveyForm.addEventListener('submit', function (e) {
        e.preventDefault();

        if (painOrder.length === 0) {
            document.getElementById('pain-ranking').classList.add('shake');
            setTimeout(function () {
                document.getElementById('pain-ranking').classList.remove('shake');
            }, 600);
            return;
        }

        var data = new FormData(surveyForm);
        var submitBtn = surveyForm.querySelector('.survey-submit');
        submitBtn.disabled = true;
        submitBtn.textContent = '...';

        fetch(API_URL + '/api/waitlist/survey', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                email: lastSignupEmail,
                info_source: data.get('info_source'),
                main_pain: painOrder.join(','),
                willingness: data.get('willingness'),
            }),
        })
            .then(function () {
                surveyContent.hidden = true;
                surveyDone.hidden = false;
                setTimeout(closeSurvey, 3000);
            })
            .catch(function () {
                surveyContent.hidden = true;
                surveyDone.hidden = false;
                setTimeout(closeSurvey, 3000);
            });
    });

    // ── Waitlist Forms ────────────────────────────
    document.querySelectorAll('.waitlist-form').forEach(function (form) {
        form.addEventListener('submit', function (e) {
            e.preventDefault();

            var input = form.querySelector('.waitlist-form__input');
            var btn = form.querySelector('.waitlist-form__btn');
            var success = form.querySelector('.waitlist-form__success');
            var error = form.querySelector('.waitlist-form__error');
            var email = input.value.trim();

            if (!email) return;

            btn.disabled = true;
            btn.textContent = '...';
            error.hidden = true;

            var payload = { email: email };
            if (utmData.utm_source) payload.utm_source = utmData.utm_source;
            if (utmData.utm_medium) payload.utm_medium = utmData.utm_medium;
            if (utmData.utm_campaign) payload.utm_campaign = utmData.utm_campaign;

            fetch(API_URL + '/api/waitlist', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify(payload),
            })
                .then(function (res) {
                    if (!res.ok) {
                        return res.json().then(function (data) {
                            throw new Error(data.detail || 'Erreur');
                        });
                    }
                    return res.json();
                })
                .then(function (data) {
                    console.log('[Facteur] waitlist response:', JSON.stringify(data));
                    input.value = '';
                    btn.textContent = 'Rejoindre la waitlist';
                    btn.disabled = true;

                    // Show survey unless backend explicitly says duplicate
                    if (data.is_new === false) {
                        console.log('[Facteur] duplicate email, showing success');
                        success.hidden = false;
                    } else {
                        console.log('[Facteur] new email, opening survey');
                        openSurvey(email);
                    }
                })
                .catch(function (err) {
                    console.error('[Facteur] waitlist error:', err);
                    error.textContent = err.message === 'Erreur'
                        ? 'Une erreur est survenue. Réessaie.'
                        : err.message;
                    error.hidden = false;
                    btn.textContent = 'Rejoindre la waitlist';
                    btn.disabled = false;
                });
        });
    });

    // ── Smooth scroll for anchor links ────────────
    document.querySelectorAll('a[href^="#"]').forEach(function (link) {
        link.addEventListener('click', function (e) {
            var target = document.querySelector(link.getAttribute('href'));
            if (target) {
                e.preventDefault();
                target.scrollIntoView({ behavior: 'smooth' });
            }
        });
    });
})();

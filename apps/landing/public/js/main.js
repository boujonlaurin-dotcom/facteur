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

    // ── Section Nav ───────────────────────────────
    var sectionNav = document.getElementById('section-nav');
    var navItems = sectionNav.querySelectorAll('.section-nav__item');
    var trackedSections = [];

    navItems.forEach(function (item) {
        var id = item.getAttribute('data-section');
        var el = document.getElementById(id);
        if (el) trackedSections.push({ id: id, el: el });
    });

    var scrollIdleTimer = null;

    function updateActiveSection() {
        var scrollY = window.scrollY;
        var heroBottom = document.getElementById('hero').offsetHeight;

        // Show/hide nav based on hero + idle
        if (scrollY > heroBottom * 0.6) {
            sectionNav.classList.add('is-visible');
            sectionNav.classList.remove('is-idle');

            clearTimeout(scrollIdleTimer);
            scrollIdleTimer = setTimeout(function () {
                sectionNav.classList.add('is-idle');
            }, 1500);
        } else {
            sectionNav.classList.remove('is-visible');
        }

        // Find active section
        var activeId = 'hero';
        for (var i = trackedSections.length - 1; i >= 0; i--) {
            var section = trackedSections[i];
            if (scrollY >= section.el.offsetTop - 120) {
                activeId = section.id;
                break;
            }
        }

        navItems.forEach(function (item) {
            if (item.getAttribute('data-section') === activeId) {
                item.classList.add('is-active');
            } else {
                item.classList.remove('is-active');
            }
        });
    }

    window.addEventListener('scroll', updateActiveSection, { passive: true });
    updateActiveSection();

    // ── Waitlist Count (social proof) ─────────────
    (function loadWaitlistCount() {
        var badge = document.getElementById('social-proof');
        var countEl = document.getElementById('waitlist-count');
        if (!badge || !countEl) return;

        fetch(API_URL + '/api/waitlist/count')
            .then(function (res) { return res.json(); })
            .then(function (data) {
                var realCount = data.count || 0;
                if (realCount < 3) return;
                var displayed = realCount * 3 + 1;
                badge.hidden = false;
                // Animate count up
                var duration = 1200;
                var start = performance.now();
                function step(now) {
                    var progress = Math.min((now - start) / duration, 1);
                    var eased = 1 - Math.pow(1 - progress, 3);
                    countEl.textContent = Math.round(eased * displayed);
                    if (progress < 1) requestAnimationFrame(step);
                }
                requestAnimationFrame(step);
            })
            .catch(function () { /* silently ignore */ });
    })();

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
        surveyModal.style.display = '';
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

    // ── Radio highlight (Q3) ──────────────────────
    surveyForm.querySelectorAll('input[type="radio"]').forEach(function (radio) {
        radio.addEventListener('change', function () {
            var name = radio.getAttribute('name');
            surveyForm.querySelectorAll('input[name="' + name + '"]').forEach(function (r) {
                r.closest('.survey-option').classList.remove('is-checked');
            });
            radio.closest('.survey-option').classList.add('is-checked');
        });
    });

    // ── Checkbox highlight (Q1) ─────────────────
    surveyForm.querySelectorAll('input[type="checkbox"]').forEach(function (cb) {
        cb.addEventListener('change', function () {
            if (cb.checked) {
                cb.closest('.survey-option').classList.add('is-checked');
            } else {
                cb.closest('.survey-option').classList.remove('is-checked');
            }
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

        // Collect checked info_source checkboxes
        var infoSources = [];
        surveyForm.querySelectorAll('input[name="info_source"]:checked').forEach(function (cb) {
            infoSources.push(cb.value);
        });

        fetch(API_URL + '/api/waitlist/survey', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                email: lastSignupEmail,
                info_source: infoSources.join(','),
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
                    input.value = '';
                    btn.textContent = 'Rejoindre la waitlist';
                    btn.disabled = true;

                    // Show survey unless backend explicitly says duplicate
                    if (data.is_new === false) {
                        success.hidden = false;
                    } else {
                        openSurvey(email);
                    }
                })
                .catch(function (err) {
                    error.textContent = err.message === 'Erreur'
                        ? 'Une erreur est survenue. Réessaie.'
                        : err.message;
                    error.hidden = false;
                    btn.textContent = 'Rejoindre la waitlist';
                    btn.disabled = false;
                });
        });
    });

    // ── FAQ Accordion ─────────────────────────────
    document.querySelectorAll('.faq__question').forEach(function (btn) {
        btn.addEventListener('click', function () {
            var item = btn.closest('.faq__item');
            var wasOpen = item.classList.contains('is-open');
            // Close all
            document.querySelectorAll('.faq__item.is-open').forEach(function (el) {
                el.classList.remove('is-open');
            });
            // Toggle clicked
            if (!wasOpen) item.classList.add('is-open');
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

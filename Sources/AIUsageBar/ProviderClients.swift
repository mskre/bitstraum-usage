import Foundation

@MainActor
protocol ProviderClient {
    var id: ProviderID { get }
    func refresh(using automation: WebAutomationService) async throws -> ProviderUsageCard
}

@MainActor
struct ScriptBackedProviderClient: ProviderClient {
    let id: ProviderID
    let script: String
    let navigateTo: URL

    func refresh(using automation: WebAutomationService) async throws -> ProviderUsageCard {
        let raw = try await automation.evaluateJSON(for: id, at: navigateTo, script: script)
        let data = Data(raw.utf8)
        let r: ProviderScrapeResult
        do {
            r = try JSONDecoder().decode(ProviderScrapeResult.self, from: data)
        } catch {
            throw ProviderError.invalidPayload("\(id.title): unreadable response")
        }

        if r.authenticated == false {
            throw ProviderError.authRequired(r.statusMessage ?? "Sign in to \(id.title)")
        }

        var limits: [UsageLimit] = []

        if let scraped = r.limits, !scraped.isEmpty {
            for s in scraped {
                let frac: Double?
                if let f = s.fraction {
                    frac = f.bounded(to: 0...1)
                } else if let t = s.total, t > 0, let rem = s.remaining {
                    frac = (rem / t).bounded(to: 0...1)
                } else {
                    frac = nil
                }
                limits.append(UsageLimit(
                    id: s.id, label: s.label,
                    remaining: s.remaining, total: s.total,
                    fraction: frac, resetLabel: s.resetLabel
                ))
            }
        } else if let total = r.total, total > 0 {
            let rem = r.remaining ?? (total - (r.used ?? 0))
            let frac = (rem / total).bounded(to: 0...1)
            limits.append(UsageLimit(
                id: "primary", label: r.headline ?? "\(id.shortTitle) usage",
                remaining: rem, total: total, fraction: frac, resetLabel: r.resetText
            ))
        }

        return ProviderUsageCard(
            id: id,
            planName: r.planName?.trimmedNonEmpty ?? id.shortTitle,
            statusMessage: r.statusMessage?.trimmedNonEmpty ?? "OK",
            limits: limits, state: .ready,
            lastUpdated: Date(), authenticated: true
        )
    }
}

enum ProviderFactory {
    static func makeAll() -> [ProviderID: any ProviderClient] {
        [
            .chatgpt: ScriptBackedProviderClient(id: .chatgpt, script: ProviderScripts.chatGPT, navigateTo: ProviderID.chatgpt.usageURL),
            .claude: ScriptBackedProviderClient(id: .claude, script: ProviderScripts.claude, navigateTo: ProviderID.claude.usageURL),
            .gemini: ScriptBackedProviderClient(id: .gemini, script: ProviderScripts.gemini, navigateTo: ProviderID.gemini.usageURL),
            .openrouter: ScriptBackedProviderClient(id: .openrouter, script: ProviderScripts.openRouter, navigateTo: ProviderID.openrouter.usageURL),
        ]
    }
}

// MARK: - Shared scraping logic injected into all DOM-based scripts.
// No hardcoded plan names, section headers, or provider-specific skip lists.
// Everything is pattern-matched dynamically from whatever the page contains.

enum ProviderScripts {

    /// Generic DOM scraper. Finds all "X% <keyword>" patterns in page text,
    /// grabs the nearest preceding text as a label, and the nearest following
    /// reset/renewal line. Plan name is extracted from the first line that looks
    /// like a plan descriptor (contains parentheses with multiplier, or sits
    /// near the word "plan").
    ///
    /// `pctKeywords` is a regex fragment like "igjen|remaining|left" or "used".
    /// `fractionFromPct` is a JS expression: either `pct / 100` (for "remaining")
    /// or `(100 - pct) / 100` (for "used").
    private static func domScraper(pctKeywords: String, fractionExpr: String, fallbackPlan: String) -> String {
        return """
        try {
          var text = "";
          try { text = document.body.innerText || ""; } catch(e) { text = ""; }

          if (text.length < 100) {
            return JSON.stringify({ authenticated: false, statusMessage: "Login required" });
          }

          // Detect login/unauthenticated pages by looking for sign-in keywords
          // combined with the ABSENCE of any usage percentage data
          var hasLoginKeywords = /continue with (google|email|apple)|sign in|sign up|log in|try claude|get started/i.test(text);
          var hasPctData = new RegExp("\\\\d{1,3}\\\\s*%\\\\s*(\(pctKeywords))", "i").test(text);

          if (hasLoginKeywords && !hasPctData) {
            return JSON.stringify({ authenticated: false, statusMessage: "Sign in required (login page detected)" });
          }

          // Dynamic plan detection from the page title area
          // Look for "Name (Nx)" multiplier pattern first, then "Xxx plan" but skip
          // generic words that aren't actual plan names
          var planName = "\(fallbackPlan)";
          var pm = text.match(/[A-Za-z]+\\s*\\(\\d+x\\)/);
          if (pm) { planName = pm[0]; }
          else {
            // Match capitalized word + "plan" but skip generic words
            var planMatches = text.match(/\\b[A-Z][a-z]+\\s+plan\\b/g) || [];
            for (var pi = 0; pi < planMatches.length; pi++) {
              var w = planMatches[pi].split(" ")[0].toLowerCase();
              if (w === "your" || w === "the" || w === "a" || w === "this" || w === "explore" || w === "our") continue;
              planName = planMatches[pi];
              break;
            }
          }

          var limits = [];
          var globalPct = new RegExp("(\\\\d{1,3})\\\\s*%\\\\s*(\(pctKeywords))", "gi");
          var match;
          while ((match = globalPct.exec(text)) !== null) {
            var pct = parseInt(match[1], 10);
            var fraction = \(fractionExpr);
            var pos = match.index;

            // Label: nearest non-trivial text line before the match
            var before = text.substring(Math.max(0, pos - 300), pos);
            var bLines = before.split("\\n").map(function(l) { return l.trim(); }).filter(function(l) { return l.length > 0; });
            var label = "Usage limit";
            for (var j = bLines.length - 1; j >= 0; j--) {
              var c = bLines[j];
              if (c.match(/^\\d+\\s*%/) || c.length < 3) continue;
              label = c;
              break;
            }

            // Reset: nearest line after the match containing time/date keywords
            var aStart = pos + match[0].length;
            var after = text.substring(aStart, Math.min(text.length, aStart + 200));
            var aLines = after.split("\\n").map(function(l) { return l.trim(); }).filter(function(l) { return l.length > 0; });
            var resetLabel = null;
            for (var k = 0; k < aLines.length && k < 3; k++) {
              if (aLines[k].match(/tilbakestilles|resets?|renews?/i)) { resetLabel = aLines[k]; break; }
            }

            var id = label.toLowerCase().replace(/[^a-z0-9]+/g, "-").substring(0, 40);
            limits.push({
              id: id || ("limit-" + limits.length),
              label: label,
              remaining: null, total: null,
              fraction: fraction,
              resetLabel: resetLabel
            });
          }

          if (limits.length === 0) {
            var preview = text.substring(0, 500).replace(/\\n/g, " | ");
            return JSON.stringify({
              authenticated: true,
              planName: planName,
              statusMessage: "Page[" + text.length + "]: " + preview,
              limits: []
            });
          }

          return JSON.stringify({
            authenticated: true,
            planName: planName,
            statusMessage: "Live",
            limits: limits
          });
        } catch(e) {
          return JSON.stringify({ authenticated: false, statusMessage: "Error: " + String(e) });
        }
        """
    }

    // ChatGPT: "93% igjen/remaining" → show 7% used (bar fills with usage)
    static let chatGPT: String = domScraper(
        pctKeywords: "igjen|remaining|left",
        fractionExpr: "(100 - pct) / 100",
        fallbackPlan: "ChatGPT"
    )

    // Claude: "33% used" → show 33% used (bar fills with usage)
    static let claude: String = domScraper(
        pctKeywords: "used",
        fractionExpr: "pct / 100",
        fallbackPlan: "Claude"
    )

    // Gemini: no known usage counter, just detect sign-in state
    static let gemini = #"""
    try {
      var text = "";
      try { text = document.body.innerText || ""; } catch(e) { text = ""; }
      if (text.length < 100) {
        return JSON.stringify({ authenticated: false, statusMessage: "Gemini login required" });
      }

      // Dynamic plan detection
      var plan = "Gemini";
      var pm = text.match(/[A-Za-z]+\s*\(\d+x\)/);
      if (pm) { plan = pm[0]; }
      else {
        pm = text.match(/[A-Za-z]+\s+plan\b/i);
        if (pm) { plan = pm[0]; }
      }

      return JSON.stringify({
        authenticated: true, planName: plan, statusMessage: "Connected",
        limits: [{ id: "plan", label: plan + " active", remaining: null, total: null, fraction: null, resetLabel: "No usage counter exposed by this provider" }]
      });
    } catch(e) {
      return JSON.stringify({ authenticated: false, statusMessage: "Error: " + String(e) });
    }
    """#

    // OpenRouter: direct API, no DOM scraping needed
    static let openRouter = #"""
    try {
      var resp = await fetch("https://openrouter.ai/api/v1/credits", { credentials: "include" });
      if (resp.status === 401) return JSON.stringify({ authenticated: false, statusMessage: "OpenRouter login required" });
      if (!resp.ok) return JSON.stringify({ authenticated: true, statusMessage: "HTTP " + resp.status, limits: [] });
      var json = await resp.json();
      var d = json.data || json;
      var total = Number(d.total_credits || d.total || 0);
      var used = Number(d.total_usage || d.used || 0);
      var rem = Math.max(total - used, 0);
      var frac = total > 0 ? rem / total : null;
      return JSON.stringify({
        authenticated: true, planName: "OpenRouter", statusMessage: "Live",
        limits: [{ id: "credits", label: "$" + rem.toFixed(2) + " remaining", remaining: rem, total: total, fraction: frac, resetLabel: "$" + used.toFixed(2) + " used of $" + total.toFixed(2) }]
      });
    } catch(e) {
      return JSON.stringify({ authenticated: false, statusMessage: "Error: " + String(e) });
    }
    """#
}

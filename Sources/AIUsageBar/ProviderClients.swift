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
    var waitForDOM: Bool = true

    func refresh(using automation: WebAutomationService) async throws -> ProviderUsageCard {
        let raw = try await automation.evaluateJSON(for: id, at: navigateTo, script: script, waitForDOM: waitForDOM)
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
                id: "primary", label: r.headline ?? "\(id.title) usage",
                remaining: rem, total: total, fraction: frac, resetLabel: r.resetText
            ))
        }

        return ProviderUsageCard(
            id: id,
            planName: r.planName?.trimmedNonEmpty ?? id.title,
            statusMessage: r.statusMessage?.trimmedNonEmpty ?? "OK",
            limits: limits, state: .ready,
            lastUpdated: Date(), authenticated: true,
            email: r.email?.trimmedNonEmpty
        )
    }
}

/// Fetches Claude usage via the Anthropic API using Claude Code OAuth credentials.
@MainActor
struct ClaudeAPIClient: ProviderClient {
    let id: ProviderID = .claude

    func refresh(using automation: WebAutomationService) async throws -> ProviderUsageCard {
        guard let creds = KeychainHelper.readClaudeCodeCredentials() else {
            throw ProviderError.authRequired("Install Claude Code and run `claude` to authenticate")
        }
        guard KeychainHelper.isTokenValid(creds) else {
            throw ProviderError.authRequired("Claude Code token expired -- run `claude` to refresh")
        }

        let planName = KeychainHelper.planName(from: creds)
        let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!
        let accountURL = URL(string: "https://api.anthropic.com/api/oauth/account")!

        let usageRequest: URLRequest = {
            var request = URLRequest(url: usageURL)
            request.setValue("Bearer \(creds.accessToken)", forHTTPHeaderField: "Authorization")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
            request.setValue("claude-cli/2.1.80 (external, cli)", forHTTPHeaderField: "User-Agent")
            request.timeoutInterval = 10
            return request
        }()

        let accountRequest: URLRequest = {
            var request = URLRequest(url: accountURL)
            request.setValue("Bearer \(creds.accessToken)", forHTTPHeaderField: "Authorization")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
            request.setValue("claude-cli/2.1.80 (external, cli)", forHTTPHeaderField: "User-Agent")
            request.timeoutInterval = 10
            return request
        }()

        async let usageResult = URLSession.shared.data(for: usageRequest)
        async let accountResult = URLSession.shared.data(for: accountRequest)

        let (data, response) = try await usageResult

        guard let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 200 else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw ProviderError.invalidPayload("API returned \(status)")
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ProviderError.invalidPayload("Invalid JSON from usage API")
        }

        var limits: [UsageLimit] = []

        let sections: [(key: String, label: String)] = [
            ("five_hour", "Current session"),
            ("seven_day", "Current week (all models)"),
            ("seven_day_sonnet", "Current week (Sonnet only)"),
        ]

        for (key, label) in sections {
            guard let section = json[key] as? [String: Any],
                  let utilization = section["utilization"] as? Double else { continue }

            let fraction = (utilization / 100).clamped(to: 0...1)
            var resetLabel: String? = nil
            if let resetsAt = section["resets_at"] as? String,
               let date = parseISO8601Date(resetsAt) {
                let formatter = RelativeDateTimeFormatter()
                formatter.unitsStyle = .full
                resetLabel = "Resets \(formatter.localizedString(for: date, relativeTo: Date()))"
            }

            limits.append(UsageLimit(
                id: key, label: label,
                remaining: nil, total: nil,
                fraction: fraction, resetLabel: resetLabel
            ))
        }

        var email: String? = nil
        if let (accountData, accountResponse) = try? await accountResult,
           let httpResp = accountResponse as? HTTPURLResponse,
           httpResp.statusCode == 200,
           let accountJSON = try? JSONSerialization.jsonObject(with: accountData) as? [String: Any] {
            email = accountJSON["email_address"] as? String
        }

        return ProviderUsageCard(
            id: .claude,
            planName: planName,
            statusMessage: "Live",
            limits: limits, state: .ready,
            lastUpdated: Date(), authenticated: true,
            email: email
        )
    }
}

@MainActor
struct OpenAICodexClient: ProviderClient {
    let id: ProviderID = .chatgpt

    func refresh(using automation: WebAutomationService) async throws -> ProviderUsageCard {
        guard OpenAIAuthHelper.readCodexCredentials() != nil else {
            throw ProviderError.authRequired("Install Codex and sign in with ChatGPT")
        }
        let creds = try await OpenAIAuthHelper.refreshCodexCredentialsIfNeeded()

        let url = URL(string: "https://chatgpt.com/backend-api/wham/usage")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(creds.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(creds.accountID, forHTTPHeaderField: "ChatGPT-Account-Id")
        request.setValue("codex-cli/0.120.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 10

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 200 else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw ProviderError.invalidPayload("OpenAI usage API returned \(status)")
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ProviderError.invalidPayload("Invalid JSON from OpenAI usage API")
        }

        let planType = (json["plan_type"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? creds.planType
        let planName = OpenAIAuthHelper.planDisplayName(fromPlanType: planType)
        var limits: [UsageLimit] = []

        if let rateLimit = json["rate_limit"] as? [String: Any] {
            if let primary = rateLimit["primary_window"] as? [String: Any],
               let usedPercent = primary["used_percent"] as? Double {
                let windowSeconds = primary["limit_window_seconds"] as? Double
                let resetAfter = primary["reset_after_seconds"] as? Double
                limits.append(UsageLimit(
                    id: "primary",
                    label: formatWindowLabel(windowSeconds),
                    remaining: nil,
                    total: nil,
                    fraction: (usedPercent / 100).clamped(to: 0...1),
                    resetLabel: formatResetLabel(resetAfter)
                ))
            }

            if let secondary = rateLimit["secondary_window"] as? [String: Any],
               let usedPercent = secondary["used_percent"] as? Double {
                let resetAfter = secondary["reset_after_seconds"] as? Double
                limits.append(UsageLimit(
                    id: "secondary",
                    label: "Weekly limit",
                    remaining: nil,
                    total: nil,
                    fraction: (usedPercent / 100).clamped(to: 0...1),
                    resetLabel: formatResetLabel(resetAfter)
                ))
            }
        }

        if let additional = json["additional_rate_limits"] as? [[String: Any]] {
            for item in additional {
                let limitName = (item["limit_name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                guard let name = limitName, !name.isEmpty,
                      let rateLimit = item["rate_limit"] as? [String: Any] else { continue }

                if let primary = rateLimit["primary_window"] as? [String: Any],
                   let usedPercent = primary["used_percent"] as? Double {
                    let windowSeconds = primary["limit_window_seconds"] as? Double
                    let resetAfter = primary["reset_after_seconds"] as? Double
                    limits.append(UsageLimit(
                        id: name.lowercased().replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression) + "-primary",
                        label: "\(name) \(formatWindowSuffix(windowSeconds))",
                        remaining: nil,
                        total: nil,
                        fraction: (usedPercent / 100).clamped(to: 0...1),
                        resetLabel: formatResetLabel(resetAfter)
                    ))
                }

                if let secondary = rateLimit["secondary_window"] as? [String: Any],
                   let usedPercent = secondary["used_percent"] as? Double {
                    let resetAfter = secondary["reset_after_seconds"] as? Double
                    limits.append(UsageLimit(
                        id: name.lowercased().replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression) + "-secondary",
                        label: "\(name) Weekly",
                        remaining: nil,
                        total: nil,
                        fraction: (usedPercent / 100).clamped(to: 0...1),
                        resetLabel: formatResetLabel(resetAfter)
                    ))
                }
            }
        }

        return ProviderUsageCard(
            id: .chatgpt,
            planName: planName,
            statusMessage: limits.isEmpty ? "Codex connected" : "Live",
            limits: limits,
            state: .ready,
            lastUpdated: Date(),
            authenticated: true,
            email: (json["email"] as? String) ?? creds.email
        )
    }

    private func formatWindowLabel(_ seconds: Double?) -> String {
        let suffix = formatWindowSuffix(seconds)
        return suffix.isEmpty ? "Usage limit" : "\(suffix) limit"
    }

    private func formatWindowSuffix(_ seconds: Double?) -> String {
        guard let seconds, seconds > 0 else { return "" }
        let hours = Int((seconds / 3600).rounded())
        if hours < 24 { return "\(hours)h" }
        let days = Int((Double(hours) / 24).rounded())
        return "\(days)d"
    }

    private func formatResetLabel(_ seconds: Double?) -> String? {
        guard let seconds, seconds > 0 else { return nil }
        let minutes = Int((seconds / 60).rounded())
        if minutes < 60 { return "Resets in \(minutes) min" }
        let hours = minutes / 60
        let remMinutes = minutes % 60
        if hours < 24 { return "Resets in \(hours)h \(remMinutes)m" }
        let days = hours / 24
        let remHours = hours % 24
        return "Resets in \(days)d \(remHours)h" }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

private func parseISO8601Date(_ value: String) -> Date? {
    let fractional = ISO8601DateFormatter()
    fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = fractional.date(from: value) {
        return date
    }

    let plain = ISO8601DateFormatter()
    plain.formatOptions = [.withInternetDateTime]
    return plain.date(from: value)
}

enum ProviderFactory {
    @MainActor static func makeAll() -> [ProviderID: any ProviderClient] {
        let chatGPTClient: any ProviderClient
        if OpenAIAuthHelper.readCodexCredentials() != nil {
            chatGPTClient = OpenAICodexClient()
        } else {
            chatGPTClient = ScriptBackedProviderClient(id: .chatgpt, script: ProviderScripts.chatGPT, navigateTo: ProviderID.chatgpt.usageURL, waitForDOM: false)
        }

        // For Claude: use the API client if Claude Code credentials exist, otherwise fall back to browser scraping
        let claudeClient: any ProviderClient
        if KeychainHelper.readClaudeCodeCredentials() != nil {
            claudeClient = ClaudeAPIClient()
        } else {
            claudeClient = ScriptBackedProviderClient(
                id: .claude, script: ProviderScripts.claude,
                navigateTo: ProviderID.claude.usageURL
            )
        }

        return [
            .chatgpt: chatGPTClient,
            .claude: claudeClient,
        ]
    }
}

// MARK: - DOM extraction scripts for provider usage pages

enum ProviderScripts {

    /// Builds a JS script that extracts usage percentages, labels, and
    /// reset times from a provider's usage page.
    ///
    /// - Parameters:
    ///   - pctKeywords: Regex fragment matching the keyword after a percentage (e.g. "used", "remaining").
    ///   - fractionExpr: JS expression converting the parsed percentage to a 0-1 fraction.
    private static func domScraper(pctKeywords: String, fractionExpr: String, fallbackPlan: String, emailFetchScript: String? = nil) -> String {
        // Double-escaped: Swift \\\\d → string value \\d → JS new RegExp("\\d") → regex \d
        let pctRegex = "(\\\\d{1,3})\\\\s*%\\\\s*(\(pctKeywords))"
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

          // Dynamic plan detection
          var planName = "\(fallbackPlan)";
          // 1. "Name (Nx)" multiplier pattern -- e.g. "Max (20x)", "Pro (20x)"
          var pm = text.match(/[A-Za-z]+\\s*\\(\\d+x\\)/i);
          if (pm) { planName = pm[0]; }
          // 2. "PRO" or "PLUS" or similar standalone uppercase badge
          if (planName === "\(fallbackPlan)") {
            pm = text.match(/\\bPRO\\b|\\bPLUS\\b|\\bMAX\\b|\\bTEAM\\b|\\bENTERPRISE\\b|\\bFREE\\b/);
            if (pm) { planName = pm[0].charAt(0) + pm[0].slice(1).toLowerCase(); }
          }
          // 3. "Xxx plan" but skip generic words
          if (planName === "\(fallbackPlan)") {
            var planMatches = text.match(/\\b[A-Z][a-z]+\\s+plan\\b/g) || [];
            for (var pi = 0; pi < planMatches.length; pi++) {
              var w = planMatches[pi].split(" ")[0].toLowerCase();
              if (w === "your" || w === "the" || w === "a" || w === "this" || w === "explore" || w === "our") continue;
              planName = planMatches[pi];
              break;
            }
          }

          // Extract email: try API fetch if provided, fall back to regex
          var email = null;
          \(emailFetchScript ?? "")
          if (!email) {
            var emailMatch = text.match(/[a-zA-Z0-9._%+\\-]+@[a-zA-Z0-9.\\-]+\\.[a-zA-Z]{2,}/);
            email = emailMatch ? emailMatch[0] : null;
          }

          var limits = [];
          var resetRe = new RegExp("^(tilbakestilles|resets)\\\\b", "i");
          var pctRe = new RegExp("\(pctRegex)", "i");

          var allLines = text.split("\\n").map(function(l) { return l.trim(); });

          for (var i = 0; i < allLines.length; i++) {
            var pm = allLines[i].match(pctRe);
            if (!pm) continue;

            var pct = parseInt(pm[1], 10);
            var fraction = \(fractionExpr);

            // Scan backwards: classify each line as reset or title
            var label = null;
            var resetLabel = null;
            for (var j = i - 1; j >= 0 && j >= i - 5; j--) {
              var line = allLines[j];
              if (line.length < 2) continue;
              if (line.match(/^\\d{1,3}\\s*%/)) continue;
              if (resetRe.test(line)) {
                if (!resetLabel) resetLabel = line;
                continue;
              }
              // Skip known section headers
              if (line.match(/^(Plan usage|Weekly limit|Additional|Learn more|Last updated|Extra usage)/i)) continue;
              // First non-reset, non-header line is the title
              if (!label) { label = line; break; }
            }

            // Also scan forward for reset (ChatGPT puts it after %)
            if (!resetLabel) {
              for (var k = i + 1; k < allLines.length && k <= i + 3; k++) {
                var fwd = allLines[k];
                if (fwd.length < 2) continue;
                if (resetRe.test(fwd)) { resetLabel = fwd; break; }
                if (fwd.match(/^\\d{1,3}\\s*%/)) break;
              }
            }

            if (!label) label = "Usage limit";

            // Convert absolute reset times to relative
            if (resetLabel) {
              resetLabel = (function(raw) {
                // Already relative like "Resets in 39 min" — keep as-is
                if (/resets\\s+in\\s/i.test(raw)) return raw;

                // Parse "Resets Sun 8:00 PM" or "Resets Tue 4:00 PM" etc.
                var m = raw.match(/(?:resets?)\\s+(Mon|Tue|Wed|Thu|Fri|Sat|Sun)\\w*\\s+(\\d{1,2}):(\\d{2})\\s*(AM|PM)/i);
                if (m) {
                  var days = ["Sun","Mon","Tue","Wed","Thu","Fri","Sat"];
                  var targetDay = -1;
                  for (var di = 0; di < days.length; di++) {
                    if (days[di].toLowerCase() === m[1].substring(0,3).toLowerCase()) { targetDay = di; break; }
                  }
                  if (targetDay >= 0) {
                    var h = parseInt(m[2], 10);
                    var min = parseInt(m[3], 10);
                    if (m[4].toUpperCase() === "PM" && h < 12) h += 12;
                    if (m[4].toUpperCase() === "AM" && h === 12) h = 0;

                    var now = new Date();
                    var target = new Date(now);
                    var diff = targetDay - now.getDay();
                    if (diff <= 0) diff += 7;
                    target.setDate(target.getDate() + diff);
                    target.setHours(h, min, 0, 0);

                    // If target is in the past (edge case), add 7 days
                    if (target <= now) target.setDate(target.getDate() + 7);

                    var diffSec = Math.round((target - now) / 1000);
                    if (diffSec > 0) {
                      var dMin = Math.floor(diffSec / 60);
                      if (dMin < 60) return "Resets in " + dMin + " min";
                      var dH = Math.floor(dMin / 60);
                      var rM = dMin % 60;
                      if (dH < 24) return "Resets in " + dH + "h " + rM + "m";
                      var dD = Math.floor(dH / 24);
                      return "Resets in " + dD + "d " + (dH % 24) + "h";
                    }
                  }
                }
                return raw;
              })(resetLabel);
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
              limits: [],
              email: email
            });
          }

          return JSON.stringify({
            authenticated: true,
            planName: planName,
            statusMessage: "Live",
            limits: limits,
            email: email
          });
        } catch(e) {
          return JSON.stringify({ authenticated: false, statusMessage: "Error: " + String(e) });
        }
        """
    }

    // ChatGPT: uses /backend-api/wham/usage which returns structured rate limit data
    static let chatGPT: String = #"""
    try {
      // Get access token
      var sessionResp = await fetch("https://chatgpt.com/api/auth/session", {
        credentials: "include"
      });
      if (!sessionResp.ok) {
        return JSON.stringify({ authenticated: false, statusMessage: "ChatGPT session fetch failed" });
      }
      var session = await sessionResp.json();
      var accessToken = session.accessToken || session.access_token;
      if (!accessToken) {
        return JSON.stringify({ authenticated: false, statusMessage: "ChatGPT sign-in required" });
      }
      var email = (session.user && session.user.email) ? session.user.email : null;

      // Fetch usage data
      var resp = await fetch("https://chatgpt.com/backend-api/wham/usage", {
        credentials: "include",
        headers: { "Authorization": "Bearer " + accessToken }
      });
      if (!resp.ok) {
        return JSON.stringify({ authenticated: false, statusMessage: "Usage fetch failed: HTTP " + resp.status });
      }

      var data = await resp.json();
      var planType = data.plan_type || "ChatGPT";
      var planName = planType.charAt(0).toUpperCase() + planType.slice(1);
      if (planName === "Pro") planName = "Pro (20x)";

      var limits = [];

      // Helper to format reset time
      var formatReset = function(seconds) {
        if (typeof seconds !== "number" || seconds <= 0) return null;
        var min = Math.round(seconds / 60);
        if (min < 60) return "Resets in " + min + " min";
        var h = Math.floor(min / 60);
        var m = min % 60;
        if (h < 24) return "Resets in " + h + "h " + m + "m";
        var d = Math.floor(h / 24);
        return "Resets in " + d + "d " + (h % 24) + "h";
      };

      // Helper to format window label
      var formatWindow = function(seconds) {
        if (!seconds) return "";
        var h = Math.round(seconds / 3600);
        if (h < 24) return h + "h";
        var d = Math.round(h / 24);
        return d + "d";
      };

      // Primary rate limit
      var rl = data.rate_limit;
      if (rl) {
        var pw = rl.primary_window;
        if (pw) {
          limits.push({
            id: "primary",
            label: formatWindow(pw.limit_window_seconds) + " limit",
            remaining: null, total: null,
            fraction: (pw.used_percent || 0) / 100,
            resetLabel: formatReset(pw.reset_after_seconds)
          });
        }
        var sw = rl.secondary_window;
        if (sw) {
          limits.push({
            id: "secondary",
            label: "Weekly limit",
            remaining: null, total: null,
            fraction: (sw.used_percent || 0) / 100,
            resetLabel: formatReset(sw.reset_after_seconds)
          });
        }
      }

      // Additional rate limits (e.g., GPT-5.3-Codex-Spark)
      var additional = data.additional_rate_limits || [];
      for (var i = 0; i < additional.length; i++) {
        var item = additional[i];
        var name = item.limit_name || "Additional";
        var arl = item.rate_limit;
        if (arl) {
          var apw = arl.primary_window;
          if (apw) {
            limits.push({
              id: name.toLowerCase().replace(/[^a-z0-9]+/g, "-") + "-primary",
              label: name + " " + formatWindow(apw.limit_window_seconds),
              remaining: null, total: null,
              fraction: (apw.used_percent || 0) / 100,
              resetLabel: formatReset(apw.reset_after_seconds)
            });
          }
          var asw = arl.secondary_window;
          if (asw) {
            limits.push({
              id: name.toLowerCase().replace(/[^a-z0-9]+/g, "-") + "-secondary",
              label: name + " Weekly",
              remaining: null, total: null,
              fraction: (asw.used_percent || 0) / 100,
              resetLabel: formatReset(asw.reset_after_seconds)
            });
          }
        }
      }

      return JSON.stringify({
        authenticated: true,
        planName: planName,
        statusMessage: limits.length > 0 ? "Live" : "No usage data",
        limits: limits,
        email: email
      });
    } catch(e) {
      return JSON.stringify({ authenticated: false, statusMessage: "Error: " + String(e) });
    }
    """#

    // Claude: "33% used" → show 33% used (bar fills with usage)
    static let claude: String = domScraper(
        pctKeywords: "used",
        fractionExpr: "pct / 100",
        fallbackPlan: "Anthropic",
        emailFetchScript: """
        try {
          var acctResp = await fetch("https://claude.ai/api/account", { credentials: "include" });
          if (acctResp.ok) {
            var acct = await acctResp.json();
            email = acct.email_address || null;
          }
        } catch(e) {}
        """
    )

}

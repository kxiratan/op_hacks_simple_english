import Foundation

/// One piece of page text. `id` is the index of the text node inside the page's state.
struct PageSegment: Codable, Equatable {
    let id: Int
    let text: String
}

/// What `PageScripts.collect` returns from the page.
struct PageSnapshot: Decodable {
    let title: String
    let url: String
    let segments: [PageSegment]
}

/// JavaScript that runs inside the browser's front tab.
/// Every script is a single IIFE expression whose value is a string.
/// Page state lives in `window.__easyPeasy = { nodes: [TextNode], originals: [String] }`.
enum PageScripts {

    /// Finds the page's text, remembers the originals inside the page,
    /// returns a JSON string decodable as `PageSnapshot`.
    static let collect: String = #"""
    (function(){
      var prev = window.__easyPeasy;
      if (prev && prev.nodes && prev.originals) {
        for (var p = 0; p < prev.nodes.length; p++) {
          var pn = prev.nodes[p];
          if (pn && pn.isConnected) { pn.nodeValue = prev.originals[p]; }
        }
      }
      try { delete window.__easyPeasy; } catch (e0) { window.__easyPeasy = undefined; }

      var nodes = [];
      var originals = [];
      var segments = [];
      var root = document.body;
      if (!root) {
        window.__easyPeasy = { nodes: nodes, originals: originals };
        return JSON.stringify({ title: document.title || "", url: location.href, segments: segments });
      }

      var letter;
      try { letter = new RegExp("\\p{L}", "u"); }
      catch (e1) { letter = /[A-Za-zÀ-ɏͰ-ￜ]/; }

      var skipTags = {
        script: 1, style: 1, noscript: 1, textarea: 1, input: 1, select: 1, option: 1,
        code: 1, pre: 1, svg: 1, math: 1, canvas: 1, iframe: 1, template: 1
      };
      var excludedCache = new Map();
      var visibleCache = new Map();

      function selfExcluded(el) {
        var tag = (el.localName || el.tagName || "").toLowerCase();
        if (skipTags[tag] === 1) { return true; }
        if (el.getAttribute) {
          if (el.getAttribute("aria-hidden") === "true") { return true; }
          var ce = el.getAttribute("contenteditable");
          if (ce !== null && ce.toLowerCase() !== "false") { return true; }
        }
        return false;
      }

      function excluded(el) {
        var chain = [];
        var cur = el;
        var result = false;
        while (cur && cur.nodeType === 1) {
          if (excludedCache.has(cur)) { result = excludedCache.get(cur); break; }
          chain.push(cur);
          if (selfExcluded(cur)) { result = true; break; }
          cur = cur.parentElement;
        }
        for (var i = 0; i < chain.length; i++) { excludedCache.set(chain[i], result); }
        return result;
      }

      function visible(el) {
        if (visibleCache.has(el)) { return visibleCache.get(el); }
        var ok = true;
        try {
          var cs = window.getComputedStyle(el);
          if (cs) {
            if (cs.display === "none" || cs.visibility === "hidden" || cs.visibility === "collapse") {
              ok = false;
            } else if (cs.display !== "contents" && el.getClientRects().length === 0) {
              ok = false;
            }
          }
        } catch (e2) { ok = true; }
        visibleCache.set(el, ok);
        return ok;
      }

      var walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT, null, false);
      var node;
      while ((node = walker.nextNode())) {
        var value = node.nodeValue;
        if (!value) { continue; }
        var text = value.replace(/\s+/g, " ").trim();
        if (text.length < 2) { continue; }
        if (!letter.test(text)) { continue; }
        var parent = node.parentElement;
        if (!parent) { continue; }
        if (excluded(parent)) { continue; }
        if (!visible(parent)) { continue; }
        var id = nodes.length;
        nodes.push(node);
        originals.push(value);
        segments.push({ id: id, text: text });
      }

      window.__easyPeasy = { nodes: nodes, originals: originals };
      return JSON.stringify({ title: document.title || "", url: location.href, segments: segments });
    })()
    """#

    /// Replaces the text of the given segments. Evaluates to the number applied, as a string.
    static func apply(_ items: [PageSegment]) -> String {
        let literal = jsLiteral(items)
        return #"""
        (function(){
          var state = window.__easyPeasy;
          if (!state || !state.nodes || !state.originals) { return "0"; }
          var items = \#(literal);
          var count = 0;
          for (var i = 0; i < items.length; i++) {
            var item = items[i];
            if (!item || typeof item.text !== "string") { continue; }
            var node = state.nodes[item.id];
            if (!node || !node.isConnected) { continue; }
            var text = item.text.trim();
            if (text.length === 0) { continue; }
            var original = state.originals[item.id];
            if (typeof original !== "string") { original = ""; }
            var lead = original.match(/^\s*/)[0];
            var trail = original.length > lead.length ? original.match(/\s*$/)[0] : "";
            node.nodeValue = lead + text + trail;
            count++;
          }
          return String(count);
        })()
        """#
    }

    /// Puts every original text back and forgets the state.
    /// Evaluates to the number restored, as a string.
    static let restore: String = #"""
    (function(){
      var state = window.__easyPeasy;
      if (!state || !state.nodes || !state.originals) {
        try { delete window.__easyPeasy; } catch (e0) { window.__easyPeasy = undefined; }
        return "0";
      }
      var count = 0;
      for (var i = 0; i < state.nodes.length; i++) {
        var node = state.nodes[i];
        if (node && node.isConnected) {
          node.nodeValue = state.originals[i];
          count++;
        }
      }
      try { delete window.__easyPeasy; } catch (e1) { window.__easyPeasy = undefined; }
      return String(count);
    })()
    """#

    static func decodeSnapshot(_ json: String) throws -> PageSnapshot {
        try JSONDecoder().decode(PageSnapshot.self, from: Data(json.utf8))
    }

    /// JSON for `items`, made safe to sit inside JavaScript source.
    private static func jsLiteral(_ items: [PageSegment]) -> String {
        guard let data = try? JSONEncoder().encode(items),
              let json = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return json
            .replacingOccurrences(of: "\u{2028}", with: "\\u2028")
            .replacingOccurrences(of: "\u{2029}", with: "\\u2029")
            .replacingOccurrences(of: "</", with: "<\\/")
    }
}

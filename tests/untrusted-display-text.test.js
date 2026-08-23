const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")

const pluginRoot = path.resolve(__dirname, "..")
const qmlFiles = fs.readdirSync(pluginRoot).filter(file => file.endsWith(".qml"))

function textBlocks(source) {
  const blocks = []
  const opening = /\bText\s*\{/g
  let match

  while ((match = opening.exec(source)) !== null) {
    const start = match.index
    let depth = 0
    let quote = ""
    let escaped = false
    let lineComment = false
    let blockComment = false

    for (let index = source.indexOf("{", start); index < source.length; index++) {
      const char = source[index]
      const next = source[index + 1]

      if (lineComment) {
        if (char === "\n") lineComment = false
        continue
      }
      if (blockComment) {
        if (char === "*" && next === "/") {
          blockComment = false
          index++
        }
        continue
      }
      if (quote) {
        if (escaped) escaped = false
        else if (char === "\\") escaped = true
        else if (char === quote) quote = ""
        continue
      }
      if (char === "/" && next === "/") {
        lineComment = true
        index++
        continue
      }
      if (char === "/" && next === "*") {
        blockComment = true
        index++
        continue
      }
      if (char === "\"" || char === "'") {
        quote = char
        continue
      }
      if (char === "{") depth++
      if (char === "}" && --depth === 0) {
        blocks.push(source.slice(start, index + 1))
        opening.lastIndex = index + 1
        break
      }
    }
  }

  return blocks
}

function tooltipExpressions(source) {
  const lines = source.split("\n")
  const expressions = []

  for (let index = 0; index < lines.length; index++) {
    const match = lines[index].match(/^(\s*)tooltipText\s*:/)
    if (!match) continue

    const baseIndent = match[1].length
    const expression = [lines[index]]
    while (index + 1 < lines.length) {
      const next = lines[index + 1]
      const indentation = next.match(/^\s*/)[0].length
      if (next.trim() !== "" && indentation <= baseIndent) break
      expression.push(next)
      index++
    }
    expressions.push(expression.join("\n"))
  }

  return expressions
}

const taintedText = /Model\.displayLabel\s*\(|tile\.display\.(?:label|name)|selectedDisplay\.label|monitorRow\.display\.name|\.(?:make|model|description)\b/
const untrustedTooltipData = /workspaceOwner(?:Label)?|Model\.displayLabel|selectedDisplay\.label|tile\.display\.(?:label|name)|\.(?:make|model|description)\b/
let taintedSinkCount = 0

for (const file of qmlFiles) {
  const source = fs.readFileSync(path.join(pluginRoot, file), "utf8")
  const sinks = textBlocks(source).filter(block => taintedText.test(block))
  taintedSinkCount += sinks.length

  for (const sink of sinks) {
    assert.match(
      sink,
      /textFormat\s*:\s*Text\.PlainText/,
      `${file} renders monitor-provided text without Text.PlainText:\n${sink}`
    )
  }

  for (const tooltip of tooltipExpressions(source)) {
    assert.doesNotMatch(
      tooltip,
      untrustedTooltipData,
      `${file} passes monitor-provided text into an AutoText tooltip:\n${tooltip}`
    )
  }
}

assert.ok(taintedSinkCount >= 4, "expected to audit every known monitor-derived Text sink")
console.log("untrusted display text tests passed")

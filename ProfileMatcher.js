// Deterministic monitor/profile identity matching. Connector identity, monitor
// identity, and the current runtime name stay separate; callers decide which
// confidence levels are safe to apply automatically.

function text(value) {
  return value === undefined || value === null ? "" : String(value)
}

function sortedIdentities(values) {
  return (Array.isArray(values) ? values : []).filter(function(value) {
    return value && text(value.name) !== ""
  }).slice().sort(function(left, right) {
    return text(left.name).localeCompare(text(right.name))
  })
}

function identitiesFromSnapshot(snapshot) {
  var source = snapshot || {}
  var connectors = {}
  var monitors = {}
  var topology = {}
  ;(Array.isArray(source.connectors) ? source.connectors : []).forEach(function(value) {
    if (value && value.name) connectors[value.name] = value
  })
  ;(Array.isArray(source.monitors) ? source.monitors : []).forEach(function(value) {
    if (value && value.name) monitors[value.name] = value
  })
  ;(Array.isArray(source.topology) ? source.topology : []).forEach(function(value) {
    if (value && value.name) topology[value.name] = value
  })

  return Object.keys(connectors).concat(Object.keys(monitors), Object.keys(topology))
    .filter(function(name, index, names) { return names.indexOf(name) === index })
    .sort().map(function(name) {
      var connector = connectors[name] || {}
      var monitor = monitors[name] || {}
      var live = topology[name] || {}
      return {
        name: name,
        sysfsPath: connector.sysfsPath || null,
        connectorInstance: connector.instance === undefined ? null : connector.instance,
        transport: connector.transport || "unknown",
        edidHash: monitor.edidHash || null,
        serial: monitor.serial || null,
        serialTrusted: monitor.serialTrusted === true,
        make: monitor.make || null,
        model: monitor.model || null,
        physicalWidth: monitor.physicalWidth === undefined ? null : monitor.physicalWidth,
        physicalHeight: monitor.physicalHeight === undefined ? null : monitor.physicalHeight,
        preferredMode: monitor.preferredMode || null,
        modes: Array.isArray(live.modes) ? live.modes.slice() : []
      }
    })
}

function valueCounts(values, key, predicate) {
  var counts = {}
  values.forEach(function(value) {
    if (predicate && !predicate(value)) return
    var item = text(value[key])
    if (item !== "") counts[item] = (counts[item] || 0) + 1
  })
  return counts
}

function sameConnector(saved, current) {
  var savedPath = text(saved.sysfsPath)
  var currentPath = text(current.sysfsPath)
  if (savedPath !== "" && currentPath !== "") return savedPath === currentPath
  return text(saved.name) === text(current.name)
}

function sameWeakIdentity(saved, current) {
  var fields = ["make", "model", "physicalWidth", "physicalHeight"]
  for (var i = 0; i < fields.length; i++) {
    if (text(saved[fields[i]]) === "" || text(current[fields[i]]) === ""
        || text(saved[fields[i]]) !== text(current[fields[i]])) return false
  }
  return true
}

function candidate(saved, current, counts) {
  var serial = text(saved.serial)
  var edid = text(saved.edidHash)
  var serialMatch = serial !== "" && saved.serialTrusted === true
    && current.serialTrusted === true && serial === text(current.serial)
    && counts.savedSerial[serial] === 1 && counts.currentSerial[serial] === 1
  var edidMatch = edid !== "" && edid === text(current.edidHash)
    && counts.savedEdid[edid] === 1 && counts.currentEdid[edid] === 1
  var strong = serialMatch || edidMatch
  var connectorMatch = sameConnector(saved, current)

  if (strong && connectorMatch)
    return { score: 4, status: "exact", reason: "same connector and strong monitor identity" }
  if (strong)
    return { score: 3, status: "moved", reason: "strong monitor identity moved to another connector" }

  if (sameWeakIdentity(saved, current)) {
    var savedInstance = saved.connectorInstance
    var currentInstance = current.connectorInstance
    if (savedInstance !== null && savedInstance !== undefined
        && currentInstance !== null && currentInstance !== undefined
        && Number(savedInstance) === Number(currentInstance))
      return { score: 2, status: "weak", reason: "make, model, size, and connector instance match" }
    // Retain insufficient candidates only so ties can be explained as
    // ambiguity. A single signature-only candidate is still treated as new.
    return { score: 1, status: "insufficient", reason: "only make, model, and size match" }
  }
  return null
}

function matchIdentities(savedValues, currentValues) {
  var saved = sortedIdentities(savedValues)
  var current = sortedIdentities(currentValues)
  var counts = {
    savedSerial: valueCounts(saved, "serial", function(value) { return value.serialTrusted === true }),
    currentSerial: valueCounts(current, "serial", function(value) { return value.serialTrusted === true }),
    savedEdid: valueCounts(saved, "edidHash"),
    currentEdid: valueCounts(current, "edidHash")
  }

  var proposals = current.map(function(currentIdentity) {
    var candidates = []
    saved.forEach(function(savedIdentity) {
      var evidence = candidate(savedIdentity, currentIdentity, counts)
      if (evidence) candidates.push(Object.assign({ saved: savedIdentity }, evidence))
    })
    candidates.sort(function(left, right) {
      return right.score - left.score
        || text(left.saved.name).localeCompare(text(right.saved.name))
    })
    var bestScore = candidates.length ? candidates[0].score : 0
    var best = candidates.filter(function(item) { return item.score === bestScore })
    return { current: currentIdentity, candidates: candidates, best: best, bestScore: bestScore }
  })

  // A saved identity cannot be silently assigned to multiple current outputs.
  var claimed = {}
  proposals.forEach(function(proposal) {
    if (proposal.best.length === 1 && proposal.bestScore >= 2) {
      var name = text(proposal.best[0].saved.name)
      claimed[name] = (claimed[name] || 0) + 1
    }
  })

  var matches = proposals.map(function(proposal) {
    var currentName = text(proposal.current.name)
    var candidateNames = proposal.best.map(function(item) { return text(item.saved.name) }).sort()
    if (proposal.best.length > 1) {
      return { currentName: currentName, savedName: null, status: "ambiguous",
        reason: "multiple saved displays have equal identity evidence",
        candidateSavedNames: candidateNames, requiresModeRevalidation: false }
    }
    if (proposal.best.length === 1 && proposal.bestScore >= 2) {
      var best = proposal.best[0]
      var savedName = text(best.saved.name)
      if (claimed[savedName] > 1) {
        return { currentName: currentName, savedName: null, status: "ambiguous",
          reason: "one saved display matches multiple connected outputs",
          candidateSavedNames: [savedName], requiresModeRevalidation: false }
      }
      return { currentName: currentName, savedName: savedName, status: best.status,
        reason: best.reason, candidateSavedNames: [savedName],
        requiresModeRevalidation: best.status === "moved" }
    }
    return { currentName: currentName, savedName: null, status: "new",
      reason: proposal.best.length === 1
        ? "identity evidence is insufficient for automatic assignment"
        : "no saved display identity matches",
      candidateSavedNames: candidateNames, requiresModeRevalidation: false }
  })

  var assigned = {}
  matches.forEach(function(match) { if (match.savedName) assigned[match.savedName] = true })
  return {
    matches: matches,
    unmatchedSavedNames: saved.map(function(value) { return text(value.name) })
      .filter(function(name) { return !assigned[name] })
  }
}

function sameNames(left, right) {
  return left.slice().sort().join("\n") === right.slice().sort().join("\n")
}

function profileStatus(store, snapshot) {
  var current = identitiesFromSnapshot(snapshot)
  var currentNames = current.map(function(value) { return value.name })
  var profiles = store && Array.isArray(store.profiles) ? store.profiles.slice() : []
  var activeId = text(store && store.activeProfileId)
  var rank = { exact: 5, moved: 4, weak: 3, ambiguous: 2, new: 1 }

  var candidates = profiles.map(function(profile) {
    var policy = profile.matchPolicy || {}
    var saved = Array.isArray(policy.identities) ? policy.identities : []
    if (saved.length === 0) {
      var legacyExact = sameNames(Array.isArray(profile.connectedSet) ? profile.connectedSet : [], currentNames)
      return { status: legacyExact ? "exact" : "new", profileId: text(profile.id),
        legacyConnectorOnly: true, matches: [], unmatchedSavedNames: [] }
    }

    var result = matchIdentities(saved, current)
    var statuses = result.matches.map(function(match) { return match.status })
    var complete = result.matches.length === current.length && result.unmatchedSavedNames.length === 0
    var status = "new"
    if (complete && statuses.every(function(value) { return value === "exact" })) status = "exact"
    else if (complete && statuses.some(function(value) { return value === "moved" })
             && statuses.every(function(value) { return value === "exact" || value === "moved" })) status = "moved"
    else if (statuses.some(function(value) { return value === "ambiguous" })) status = "ambiguous"
    else if (complete && statuses.some(function(value) { return value === "weak" })
             && statuses.every(function(value) { return value === "exact" || value === "weak" })) status = "weak"
    return { status: status, profileId: text(profile.id), legacyConnectorOnly: false,
      matches: result.matches, unmatchedSavedNames: result.unmatchedSavedNames }
  })

  candidates.sort(function(left, right) {
    return rank[right.status] - rank[left.status]
      || (right.profileId === activeId ? 1 : 0) - (left.profileId === activeId ? 1 : 0)
      || left.profileId.localeCompare(right.profileId)
  })
  return candidates.length ? candidates[0]
    : { status: "new", profileId: "", legacyConnectorOnly: false,
        matches: [], unmatchedSavedNames: [] }
}

if (typeof module !== "undefined") {
  module.exports = {
    identitiesFromSnapshot: identitiesFromSnapshot,
    matchIdentities: matchIdentities,
    profileStatus: profileStatus
  }

  if (require.main === module) {
    try {
      var command = process.argv[2]
      if (command === "identities")
        process.stdout.write(JSON.stringify(identitiesFromSnapshot(JSON.parse(process.argv[3]))) + "\n")
      else if (command === "profile-status")
        process.stdout.write(JSON.stringify(profileStatus(
          JSON.parse(process.argv[3]), JSON.parse(process.argv[4]))) + "\n")
      else process.exitCode = 2
    } catch (error) {
      process.stderr.write("Invalid profile matching input\n")
      process.exitCode = 2
    }
  }
}

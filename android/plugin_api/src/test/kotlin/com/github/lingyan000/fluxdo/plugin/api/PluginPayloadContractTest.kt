package com.github.lingyan000.fluxdo.plugin.api

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test

/** Runs as a local JVM test; no emulator, host Flutter or application APK needed. */
class PluginPayloadContractTest {
    private val emptyOperations = listOf(
        "device.snapshot",
        "network.state",
        "metaverse.capabilities",
        "reward.capabilities",
    )

    private fun rejects(operation: String, raw: String) {
        assertThrows(IllegalArgumentException::class.java) {
            PluginPayloadContract.normalize(operation, raw)
        }
    }

    @Test
    fun emptyPayloadOperationsRejectEvenHarmlessExtraFields() {
        for (operation in emptyOperations) {
            assertEquals("{}", PluginPayloadContract.normalize(operation, "{}"))
            assertEquals("{}", PluginPayloadContract.normalize(operation, " { } "))
            for (raw in listOf(
                """{"unused":null}""",
                """{"hostname":"linux.do"}""",
                """{"token":{"secret":"must-not-cross"}}""",
            )) {
                rejects(operation, raw)
            }
        }
    }

    @Test
    fun invalidJsonAndUndeclaredOperationsFailClosed() {
        for (raw in listOf("", "[]", "null", "true", "42", "\"string\"", "{", "{} trailing")) {
            rejects("device.snapshot", raw)
        }
        rejects("network.future", "{}")
        rejects("network.lookup", "{}")
        rejects("network.lookup", """{"hostname":"linux.do","cookie":"secret"}""")
        rejects("network.lookup", """{"hostname":null}""")
        rejects("network.lookup", """{"hostname":42}""")
    }

    @Test
    fun dnsLookupAcceptsOnlyNormalizedValidDnsLabels() {
        val raw = PluginPayloadContract.normalize(
            "network.lookup",
            """{"hostname":" Linux.DO. "}""",
        )
        assertEquals("Linux.DO.", JSONObject(raw).getString("hostname"))
        for (hostname in listOf(
            "", " ", ".a", "a..b", "a..", "-a.com", "a-.com",
            "a b", "a_b.com", "localhost:443", "https://linux.do",
            "a/b", "a\\nb", "${"a".repeat(64)}.com",
            listOf("a".repeat(63), "b".repeat(63), "c".repeat(63), "d".repeat(63)).joinToString("."),
        )) {
            rejects("network.lookup", JSONObject().put("hostname", hostname).toString())
        }
        val valid = PluginPayloadContract.normalize(
            "network.lookup",
            """{"hostname":"sub.example.com"}""",
        )
        assertEquals("sub.example.com", JSONObject(valid).getString("hostname"))
    }

    @Test
    fun utf8ByteSizeLimitIsEnforcedBeforeExecution() {
        val oversized = JSONObject().put("hostname", "汉".repeat(3000)).toString()
        rejects("network.lookup", oversized)
        assertThrows(IllegalArgumentException::class.java) {
            PluginPayloadContract.normalize(
                "device.snapshot",
                """{"pad":"${"x".repeat(PluginProtocol.MAX_JSON_BYTES)}"}""",
            )
        }
    }
}

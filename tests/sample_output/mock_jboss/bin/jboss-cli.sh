#!/usr/bin/env bash
cat << 'JSON_OUT'
{
    "outcome" => "success",
    "result" => {
        "step-1" => {
            "outcome" => "success",
            "result" => {
                "data-source" => {},
                "xa-data-source" => {
                    "MySQLXADS" => {
                        "statistics" => {
                            "pool" => {
                                "ActiveCount" => 20,
                                "AvailableCount" => 12,
                                "AverageBlockingTime" => 4L,
                                "AverageCreationTime" => 15L,
                                "AverageGetTime" => 2L,
                                "BlockingFailureCount" => 0,
                                "CreatedCount" => 20,
                                "DestroyedCount" => 0,
                                "IdleCount" => 12,
                                "InUseCount" => 8,
                                "MaxCreationTime" => 45L,
                                "MaxGetTime" => 18L,
                                "MaxPoolTime" => 12000L,
                                "MaxUsedCount" => 16,
                                "MaxWaitCount" => 2,
                                "MaxWaitTime" => 12L,
                                "TimedOut" => 0,
                                "TotalBlockingTime" => 24L,
                                "TotalCreationTime" => 300L,
                                "TotalGetTime" => 950L,
                                "WaitCount" => 0
                            },
                            "jdbc" => {
                                "PreparedStatementCacheAccessCount" => 1420L,
                                "PreparedStatementCacheAddCount" => 85L,
                                "PreparedStatementCacheCurrentSize" => 85,
                                "PreparedStatementCacheDeleteCount" => 0L,
                                "PreparedStatementCacheHitCount" => 1335L,
                                "PreparedStatementCacheMissCount" => 85L
                            }
                        }
                    }
                }
            }
        },
        "step-2" => {
            "outcome" => "success",
            "result" => {
                "server" => {
                    "default-server" => {
                        "http-listener" => {
                            "default" => {
                                "bytes-received" => 5242880L,
                                "bytes-sent" => 18874368L,
                                "error-count" => 2,
                                "max-processing-time" => 340L,
                                "processing-time" => 48200L,
                                "request-count" => 1250
                            }
                        }
                    }
                }
            }
        },
        "step-3" => {
            "outcome" => "success",
            "result" => {
                "worker" => {
                    "default" => {
                        "busy-task-thread-count" => 6,
                        "core-pool-size" => 16,
                        "io-thread-count" => 4,
                        "max-pool-size" => 32,
                        "queue-size" => 0,
                        "rejected-count" => 0,
                        "task-max-threads" => 32
                    }
                }
            }
        },
        "step-4" => {
            "outcome" => "success",
            "result" => {
                "number-of-aborted-transactions" => 1L,
                "number-of-application-rollbacks" => 1L,
                "number-of-committed-transactions" => 980L,
                "number-of-heuristics" => 0L,
                "number-of-inflight-transactions" => 3L,
                "number-of-nested-transactions" => 0L,
                "number-of-resource-rollbacks" => 0L,
                "number-of-system-rollbacks" => 0L,
                "number-of-timed-out-transactions" => 0L,
                "number-of-transactions" => 984L
            }
        }
    }
}
JSON_OUT

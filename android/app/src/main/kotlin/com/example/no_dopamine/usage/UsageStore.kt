package com.example.no_dopamine.usage

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper

data class StoredEvent(val time: Long, val type: Int, val app: String, val activity: String)

/** Private on-device archive. No background service or network transport. */
class UsageStore(context: Context) : SQLiteOpenHelper(context, "usage_history.db", null, 1) {
    override fun onCreate(db: SQLiteDatabase) {
        db.execSQL("""CREATE TABLE events (
            timestamp INTEGER NOT NULL, type INTEGER NOT NULL,
            package TEXT NOT NULL, activity TEXT NOT NULL,
            UNIQUE(timestamp, type, package, activity))""")
        db.execSQL("CREATE INDEX events_time ON events(timestamp)")
        db.execSQL("""CREATE TABLE coverage (
            package TEXT NOT NULL, start INTEGER NOT NULL, end INTEGER NOT NULL)""")
    }

    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) = Unit

    fun sync(events: List<StoredEvent>, packages: Set<String>, oldest: Long?, now: Long) {
        val db = writableDatabase
        val cutoff = now - 90L * 24 * 60 * 60 * 1000
        db.beginTransaction()
        try {
            db.compileStatement("INSERT OR IGNORE INTO events VALUES (?, ?, ?, ?)").use { insert ->
                for (event in events) {
                    insert.bindLong(1, event.time)
                    insert.bindLong(2, event.type.toLong())
                    insert.bindString(3, event.app)
                    insert.bindString(4, event.activity)
                    insert.executeInsert()
                }
            }
            if (oldest != null && oldest < now) {
                for (app in packages) {
                    val intervals = mutableListOf(Pair(oldest, now))
                    db.rawQuery("SELECT start, end FROM coverage WHERE package = ?", arrayOf(app)).use {
                        while (it.moveToNext()) intervals.add(Pair(it.getLong(0), it.getLong(1)))
                    }
                    intervals.sortBy { it.first }
                    val merged = mutableListOf<Pair<Long, Long>>()
                    for (interval in intervals) {
                        val last = merged.lastOrNull()
                        if (last != null && interval.first <= last.second) {
                            merged[merged.lastIndex] = Pair(last.first, maxOf(last.second, interval.second))
                        } else merged.add(interval)
                    }
                    db.delete("coverage", "package = ?", arrayOf(app))
                    for (range in merged) {
                        if (range.second <= cutoff) continue
                        db.insertOrThrow("coverage", null, ContentValues().apply {
                            put("package", app)
                            put("start", maxOf(range.first, cutoff))
                            put("end", range.second)
                        })
                    }
                }
            }
            db.delete("events", "timestamp < ?", arrayOf(cutoff.toString()))
            db.delete("coverage", "end < ?", arrayOf(cutoff.toString()))
            db.setTransactionSuccessful()
        } finally {
            db.endTransaction()
        }
    }

    fun snapshot(packages: Set<String>, start: Long, end: Long, now: Long): Map<String, Any> {
        val db = readableDatabase
        val coverage = mutableListOf<Map<String, Any>>()
        // Include the start of every relevant coverage interval to reconstruct
        // sessions crossing midnight without attributing an unknown start.
        var contextStart = start
        db.rawQuery("SELECT package, start, end FROM coverage WHERE end >= ? AND start < ?",
            arrayOf(start.toString(), end.toString())).use {
            while (it.moveToNext()) {
                val app = it.getString(0)
                if (app !in packages) continue
                val from = it.getLong(1)
                contextStart = minOf(contextStart, from)
                coverage.add(mapOf("package" to app, "start" to from, "end" to it.getLong(2)))
            }
        }
        val events = mutableListOf<Map<String, Any>>()
        db.rawQuery("SELECT timestamp, type, package, activity FROM events WHERE timestamp >= ? AND timestamp <= ? ORDER BY timestamp, rowid",
            arrayOf(contextStart.toString(), now.toString())).use {
            while (it.moveToNext()) {
                val app = it.getString(2)
                if (app.isNotEmpty() && app !in packages) continue
                events.add(mapOf("timestamp" to it.getLong(0), "type" to it.getInt(1),
                    "package" to app, "activity" to it.getString(3)))
            }
        }
        return mapOf("events" to events, "coverage" to coverage, "syncedAt" to now)
    }
}

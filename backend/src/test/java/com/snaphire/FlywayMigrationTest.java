package com.snaphire;

import io.quarkus.test.junit.QuarkusTest;
import jakarta.inject.Inject;
import org.junit.jupiter.api.Test;

import javax.sql.DataSource;
import java.sql.ResultSet;
import java.sql.Statement;
import java.util.HashSet;
import java.util.Set;

import static org.junit.jupiter.api.Assertions.assertTrue;

@QuarkusTest
public class FlywayMigrationTest {

    @Inject
    DataSource dataSource;

    @Test
    void allTablesCreatedByMigration() throws Exception {
        Set<String> expected = Set.of(
            "users", "profiles", "jobs", "matches",
            "tailored_resumes", "schedules", "notifications"
        );

        Set<String> actual = new HashSet<>();
        try (Statement stmt = dataSource.getConnection().createStatement();
             ResultSet rs = stmt.executeQuery(
                 "SELECT table_name FROM information_schema.tables WHERE table_schema = 'public' AND table_type = 'BASE TABLE'")) {
            while (rs.next()) {
                actual.add(rs.getString("table_name"));
            }
        }

        for (String table : expected) {
            assertTrue(actual.contains(table), "Missing table: " + table);
        }
    }
}

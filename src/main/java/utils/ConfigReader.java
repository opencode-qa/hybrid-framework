package utils;

import java.io.InputStream;
import java.util.Properties;

public class ConfigReader {
    private static final Properties props = new Properties();

    static {
        try (InputStream input = ConfigReader.class.getClassLoader()
                .getResourceAsStream("config.properties")) {
            if (input != null) {
                props.load(input);
            }
            // Defaults
            props.putIfAbsent("browser", "chromium");
            props.putIfAbsent("headless", "true");
            props.putIfAbsent("slowMo", "0");
            props.putIfAbsent("base.url", "https://demoqa.com");
            props.putIfAbsent("screenshot.on.failure", "true");
            props.putIfAbsent("screenshot.dir", "./screenshots");
        } catch (Exception e) {
            System.err.println("Failed to load config.properties, using defaults only.");
        }
    }

    public static String getProperty(String key) {
        String envValue = System.getenv(key.toUpperCase().replace('.', '_'));
        if (envValue != null) return envValue;
        String sysValue = System.getProperty(key);
        if (sysValue != null) return sysValue;
        return props.getProperty(key);
    }

    public static String getProperty(String key, String defaultValue) {
        String value = getProperty(key);
        return value != null ? value : defaultValue;
    }

    public static int getIntProperty(String key, int defaultValue) {
        String val = getProperty(key);
        if (val == null) return defaultValue;
        try {
            return Integer.parseInt(val);
        } catch (NumberFormatException e) {
            return defaultValue;
        }
    }

    public static boolean getBooleanProperty(String key, boolean defaultValue) {
        String val = getProperty(key);
        if (val == null) return defaultValue;
        return Boolean.parseBoolean(val);
    }
}
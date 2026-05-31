package utils;

import java.io.InputStream;
import java.util.Properties;

/**
 * Reads configuration from config.properties and supports environment overrides.
 */
public final class ConfigReader {

    private static final Properties PROPS = new Properties();

    static {
        try (InputStream input = ConfigReader.class.getClassLoader()
                .getResourceAsStream("config.properties")) {
            if (input != null) {
                PROPS.load(input);
            }
            // Defaults
            PROPS.putIfAbsent("browser", "chromium");
            PROPS.putIfAbsent("headless", "true");
            PROPS.putIfAbsent("slowMo", "0");
            PROPS.putIfAbsent("base.url", "https://demoqa.com");
            PROPS.putIfAbsent("screenshot.on.failure", "true");
            PROPS.putIfAbsent("screenshot.dir", "./screenshots");
        } catch (Exception e) {
            System.err.println("Failed to load config.properties, using defaults only.");
        }
    }

    private ConfigReader() {
        throw new UnsupportedOperationException("Utility class");
    }

    /**
     * Returns the value for a key, checking environment variables and system properties first.
     *
     * @param key the property key
     * @return the resolved value, or null if not found
     */
    public static String getProperty(final String key) {
        String envValue = System.getenv(key.toUpperCase().replace('.', '_'));
        if (envValue != null) {
            return envValue;
        }
        String sysValue = System.getProperty(key);
        if (sysValue != null) {
            return sysValue;
        }
        return PROPS.getProperty(key);
    }

    /**
     * Returns the value for a key with a default fallback.
     *
     * @param key          the property key
     * @param defaultValue the default value
     * @return the resolved value or the default
     */
    public static String getProperty(final String key, final String defaultValue) {
        String value = getProperty(key);
        return value != null ? value : defaultValue;
    }

    /**
     * Returns an integer property.
     *
     * @param key          the property key
     * @param defaultValue the default integer
     * @return the parsed integer or the default
     */
    public static int getIntProperty(final String key, final int defaultValue) {
        String val = getProperty(key);
        if (val == null) {
            return defaultValue;
        }
        try {
            return Integer.parseInt(val);
        } catch (NumberFormatException e) {
            return defaultValue;
        }
    }

    /**
     * Returns a boolean property.
     *
     * @param key          the property key
     * @param defaultValue the default boolean
     * @return the parsed boolean or the default
     */
    public static boolean getBooleanProperty(final String key, final boolean defaultValue) {
        String val = getProperty(key);
        if (val == null) {
            return defaultValue;
        }
        return Boolean.parseBoolean(val);
    }
}

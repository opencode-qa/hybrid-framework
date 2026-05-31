package utils;

import com.microsoft.playwright.Page;
import org.apache.logging.log4j.LogManager;
import org.apache.logging.log4j.Logger;

import java.nio.file.Files;
import java.nio.file.Paths;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;

/**
 * Utility for capturing screenshots during test execution.
 */
public final class ScreenshotUtil {

    /**
     * Logger for this class.
     */
    private static final Logger LOG =
            LogManager.getLogger(ScreenshotUtil.class);

    private ScreenshotUtil() {
        throw new UnsupportedOperationException("Utility class");
    }

    /**
     * Captures a screenshot and saves it to the configured directory.
     *
     * @param page     the Playwright page to capture
     * @param testName name of the test (used in the filename)
     */
    public static void captureScreenshot(
            final Page page, final String testName) {
        
        if (page == null) {
            LOG.warn("Screenshot skipped – page is null for test: {}",
                    testName);
            return;
        }

        try {
            String dir = ConfigReader.getProperty(
                    "screenshot.dir", "./screenshots");
            Files.createDirectories(Paths.get(dir));

            String timestamp = LocalDateTime.now()
                    .format(DateTimeFormatter.ofPattern("yyyyMMdd-HHmmss"));

            String path = String.format("%s/%s_%s.png",
                    dir, testName, timestamp);

            page.screenshot(new Page.ScreenshotOptions()
                    .setPath(Paths.get(path)));

            LOG.info("Screenshot saved: {}", path);

        } catch (Exception e) {
            LOG.error("Screenshot capture failed for test: {}", testName, e);
        }
    }
}
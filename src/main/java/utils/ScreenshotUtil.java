package utils;

import com.microsoft.playwright.Page;
import org.apache.logging.log4j.LogManager;
import org.apache.logging.log4j.Logger;

import java.nio.file.Files;
import java.nio.file.Paths;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;

public class ScreenshotUtil {

    private static final Logger log = LogManager.getLogger(ScreenshotUtil.class);

    public static void captureScreenshot(Page page, String testName) {

        if (page == null) {
            log.warn("Screenshot skipped – page is null for test: {}", testName);
            return;
        }

        try {
            String dir = ConfigReader.getProperty("screenshot.dir", "./screenshots");
            Files.createDirectories(Paths.get(dir));

            String timestamp = LocalDateTime.now()
                    .format(DateTimeFormatter.ofPattern("yyyyMMdd-HHmmss"));

            String path = String.format("%s/%s_%s.png", dir, testName, timestamp);

            page.screenshot(new Page.ScreenshotOptions()
                    .setPath(Paths.get(path)));

            log.info("Screenshot saved: {}", path);

        } catch (Exception e) {
            log.error("Screenshot capture failed for test: {}", testName, e);
        }
    }
}
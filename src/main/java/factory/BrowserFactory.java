package factory;

import com.microsoft.playwright.*;
import exceptions.FrameworkException;
import org.apache.logging.log4j.LogManager;
import org.apache.logging.log4j.Logger;
import utils.ConfigReader;

public class BrowserFactory {

    private static final Logger log = LogManager.getLogger(BrowserFactory.class);

    private static Playwright playwright;
    private static Browser browser;

    public static synchronized Browser getBrowser() {

        if (browser == null) {
            try {
                log.info("Initializing Playwright instance...");

                playwright = Playwright.create();

                String browserType = ConfigReader.getProperty("browser", "chromium").toLowerCase();
                boolean headless = ConfigReader.getBooleanProperty("headless", true);
                int slowMo = ConfigReader.getIntProperty("slowMo", 0);

                log.info("Browser Config -> type={}, headless={}, slowMo={}",
                        browserType, headless, slowMo);

                BrowserType.LaunchOptions options = new BrowserType.LaunchOptions()
                        .setHeadless(headless)
                        .setSlowMo(slowMo);

                switch (browserType) {
                    case "firefox":
                        browser = playwright.firefox().launch(options);
                        log.info("Firefox browser launched");
                        break;

                    case "webkit":
                        browser = playwright.webkit().launch(options);
                        log.info("WebKit browser launched");
                        break;

                    case "chromium":
                        browser = playwright.chromium().launch(options);
                        log.info("Chromium browser launched");
                        break;

                    default:
                        throw new FrameworkException("Invalid browser type in config: " + browserType);
                }

            } catch (Exception e) {
                throw new FrameworkException("Failed to initialize Playwright Browser", e);
            }
        }

        return browser;
    }

    public static synchronized Page getNewPage() {
        try {
            Page page = getBrowser().newPage();
            log.info("New page created");
            return page;
        } catch (Exception e) {
            throw new FrameworkException("Failed to create new page", e);
        }
    }

    public static synchronized void closeBrowser() {
        log.info("Closing browser session...");

        try {
            if (browser != null) {
                browser.close();
                browser = null;
                log.info("Browser closed");
            }

            if (playwright != null) {
                playwright.close();
                playwright = null;
                log.info("Playwright closed");
            }

        } catch (Exception e) {
            throw new FrameworkException("Failed during browser teardown", e);
        }
    }
}
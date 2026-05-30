package factory;

import exceptions.FrameworkException;
import org.apache.logging.log4j.LogManager;
import org.apache.logging.log4j.Logger;

import com.microsoft.playwright.Browser;
import com.microsoft.playwright.BrowserType;
import com.microsoft.playwright.Playwright;
import com.microsoft.playwright.Page;

import utils.ConfigReader;

public class BrowserFactory {

    private static final Logger log = LogManager.getLogger(BrowserFactory.class);

    private static Playwright playwright;
    private static Browser browser;

    private static final ThreadLocal<Page> currentPage = new ThreadLocal<>();

    public static synchronized Browser getBrowser() {

        if (browser == null) {
            try {
                log.info("Initializing Playwright...");

                playwright = Playwright.create();

                String browserType = ConfigReader.getProperty("browser", "chromium").toLowerCase();
                boolean headless = ConfigReader.getBooleanProperty("headless", true);
                int slowMo = ConfigReader.getIntProperty("slowMo", 0);

                log.info("Config -> browser={}, headless={}, slowMo={}",
                        browserType, headless, slowMo);

                BrowserType.LaunchOptions options = new BrowserType.LaunchOptions()
                        .setHeadless(headless)
                        .setSlowMo(slowMo);

                switch (browserType) {
                    case "firefox":
                        browser = playwright.firefox().launch(options);
                        break;
                    case "webkit":
                        browser = playwright.webkit().launch(options);
                        break;
                    case "chromium":
                        browser = playwright.chromium().launch(options);
                        break;
                    default:
                        throw new FrameworkException("Invalid browser type: " + browserType);
                }

                log.info("{} browser launched successfully", browserType);

            } catch (Exception e) {
                throw new FrameworkException("Browser initialization failed", e);
            }
        }

        return browser;
    }

    public static synchronized Page getNewPage() {
        try {
            Page page = getBrowser().newPage();
            currentPage.set(page);
            log.info("New page created");
            return page;
        } catch (Exception e) {
            throw new FrameworkException("Failed to create new page", e);
        }
    }

    public static Page getCurrentPage() {
        return currentPage.get();
    }

    public static synchronized void closeBrowser() {
        log.info("Closing browser session...");

        try {
            if (browser != null) {
                browser.close();
                browser = null;
            }

            if (playwright != null) {
                playwright.close();
                playwright = null;
            }

            currentPage.remove();

            log.info("Browser session closed successfully");

        } catch (Exception e) {
            throw new FrameworkException("Failed during browser teardown", e);
        }
    }
}
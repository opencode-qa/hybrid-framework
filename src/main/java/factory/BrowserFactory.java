package factory;

import com.microsoft.playwright.Browser;
import com.microsoft.playwright.BrowserType;
import com.microsoft.playwright.Page;
import com.microsoft.playwright.Playwright;
import exceptions.FrameworkException;
import org.apache.logging.log4j.LogManager;
import org.apache.logging.log4j.Logger;
import utils.ConfigReader;

/**
 * Factory for creating and managing Playwright browser instances.
 */
public final class BrowserFactory {

    private static final Logger LOG = LogManager.getLogger(BrowserFactory.class);
    private static Playwright playwright;
    private static Browser browser;
    private static final ThreadLocal<Page> CURRENT_PAGE = new ThreadLocal<>();

    private BrowserFactory() {
        throw new UnsupportedOperationException("Utility class");
    }

    /**
     * Returns the shared browser instance (lazy initialisation).
     *
     * @return the Playwright browser
     */
    public static synchronized Browser getBrowser() {
        if (browser == null) {
            try {
                LOG.info("Initializing Playwright...");
                playwright = Playwright.create();

                String browserType = ConfigReader.getProperty("browser", "chromium")
                        .toLowerCase();
                boolean headless = ConfigReader.getBooleanProperty("headless", true);
                int slowMo = ConfigReader.getIntProperty("slowMo", 0);

                LOG.info("Config -> browser={}, headless={}, slowMo={}",
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

                LOG.info("{} browser launched successfully", browserType);

            } catch (Exception e) {
                throw new FrameworkException("Browser initialization failed", e);
            }
        }
        return browser;
    }

    /**
     * Creates a new page and associates it with the current thread.
     *
     * @return a new Playwright page
     */
    public static synchronized Page getNewPage() {
        try {
            Page page = getBrowser().newPage();
            CURRENT_PAGE.set(page);
            LOG.info("New page created");
            return page;
        } catch (Exception e) {
            throw new FrameworkException("Failed to create new page", e);
        }
    }

    /**
     * Returns the page associated with the current thread.
     *
     * @return the current page, or null
     */
    public static Page getCurrentPage() {
        return CURRENT_PAGE.get();
    }

    /**
     * Closes the browser and Playwright instance, and removes thread-local state.
     */
    public static synchronized void closeBrowser() {
        LOG.info("Closing browser session...");
        try {
            if (browser != null) {
                browser.close();
                browser = null;
            }
            if (playwright != null) {
                playwright.close();
                playwright = null;
            }
            CURRENT_PAGE.remove();
            LOG.info("Browser session closed successfully");
        } catch (Exception e) {
            throw new FrameworkException("Failed during browser teardown", e);
        }
    }
}

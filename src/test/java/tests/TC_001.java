package tests;

import com.microsoft.playwright.Page;
import exceptions.FrameworkException;
import factory.BrowserFactory;
import org.apache.logging.log4j.LogManager;
import org.apache.logging.log4j.Logger;
import org.testng.Assert;
import org.testng.annotations.AfterTest;
import org.testng.annotations.BeforeTest;
import org.testng.annotations.Test;
import utils.ConfigReader;
import utils.ScreenshotUtil;

/**
 * Test case TC_001: Validate the Text Box form on DemoQA.
 */
public class TC_001 {

    /** * Logger for the test. 
     */
    private static final Logger LOG = LogManager.getLogger(TC_001.class);

    /** * The Playwright page instance. 
     */
    private Page page;

    /**
     * Sets up the browser and page before the test.
     */
    @BeforeTest
    public void setUp() {
        LOG.info("========== TEST SETUP STARTED ==========");
        try {
            page = BrowserFactory.getNewPage();
            LOG.info("Browser launched | Headless: {} | "
                    + "SlowMo: {}ms | Browser: {}",
                    ConfigReader.getProperty("headless"),
                    ConfigReader.getProperty("slowMo"),
                    ConfigReader.getProperty("browser"));
        } catch (Exception e) {
            LOG.error("Setup failed", e);
            throw new FrameworkException(
                    "Failed to initialise browser", e);
        }
        LOG.info("========== TEST SETUP COMPLETED ==========");
    }

    /**
     * Executes the Text Box form test.
     */
    @Test
    public void testTextBoxForm() {
        LOG.info("========== TEST EXECUTION STARTED ==========");
        final String baseUrl = ConfigReader.getProperty(
                "base.url", "https://demoqa.com");
        try {
            LOG.info("Navigating to {}", baseUrl);
            page.navigate(baseUrl);
            LOG.debug("Current URL: {}", page.url());

            LOG.info("Clicking 'Elements' card");
            page.click("div.card-body:has-text('Elements')");
            LOG.info("Clicking 'Text Box' menu");
            page.click("span.text:has-text('Text Box')");

            LOG.info("Filling form fields");
            page.fill("#userName", "John Doe");
            page.fill("#userEmail", "john.doe@test.com");
            page.fill("#currentAddress", "New Delhi, India");
            page.fill("#permanentAddress", "Bangalore, India");

            LOG.info("Submitting form");
            page.click("#submit");

            LOG.info("Verifying output section visibility");
            final boolean isVisible = page.isVisible("#output");
            LOG.info("Output visible: {}", isVisible);
            
            Assert.assertTrue(isVisible, 
                    "Output div should be visible after submission");

            final String outputText = page.textContent("#output");
            LOG.info("Output text:\n{}", outputText);
        } catch (AssertionError e) {
            LOG.error("Assertion failed", e);
            ScreenshotUtil.captureScreenshot(page, "TC_001_failure");
            throw e;
        } catch (Exception e) {
            LOG.error("Unexpected error during test execution", e);
            ScreenshotUtil.captureScreenshot(page, "TC_001_error");
            throw new FrameworkException("Test execution failed", e);
        }
        LOG.info("========== TEST EXECUTION COMPLETED ==========");
    }

    /**
     * Closes the browser after the test.
     */
    @AfterTest
    public void tearDown() {
        LOG.info("========== TEST TEARDOWN STARTED ==========");
        BrowserFactory.closeBrowser();
        LOG.info("Browser closed");
        LOG.info("========== TEST TEARDOWN COMPLETED ==========");
    }
}

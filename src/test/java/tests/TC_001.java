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

public class TC_001 {
    private static final Logger log = LogManager.getLogger(TC_001.class);
    private Page page;

    @BeforeTest
    public void setUp() {
        log.info("========== TEST SETUP STARTED ==========");
        try {
            page = BrowserFactory.getNewPage();
            log.info("Browser launched | Headless: {} | SlowMo: {}ms | Browser: {}",
                    ConfigReader.getProperty("headless"),
                    ConfigReader.getProperty("slowMo"),
                    ConfigReader.getProperty("browser"));
        } catch (Exception e) {
            log.error("Setup failed", e);
            throw new FrameworkException("Failed to initialise browser", e);
        }
        log.info("========== TEST SETUP COMPLETED ==========");
    }

    @Test
    public void testTextBoxForm() {
        log.info("========== TEST EXECUTION STARTED ==========");
        String baseUrl = ConfigReader.getProperty("base.url", "https://demoqa.com");
        try {
            log.info("Navigating to {}", baseUrl);
            page.navigate(baseUrl);
            log.debug("Current URL: {}", page.url());

            log.info("Clicking 'Elements' card");
            page.click("div.card-body:has-text('Elements')");
            log.info("Clicking 'Text Box' menu");
            page.click("span.text:has-text('Text Box')");

            log.info("Filling form fields");
            page.fill("#userName", "John Doe");
            page.fill("#userEmail", "john.doe@test.com");
            page.fill("#currentAddress", "New Delhi, India");
            page.fill("#permanentAddress", "Bangalore, India");

            log.info("Submitting form");
            page.click("#submit");

            log.info("Verifying output section visibility");
            boolean isVisible = page.isVisible("#output");
            log.info("Output visible: {}", isVisible);
            Assert.assertTrue(isVisible, "Output div should be visible after submission");

            String outputText = page.textContent("#output");
            log.info("Output text:\n{}", outputText);
        } catch (AssertionError e) {
            log.error("Assertion failed", e);
            ScreenshotUtil.captureScreenshot(page, "TC_001_failure");
            throw e;
        } catch (Exception e) {
            log.error("Unexpected error during test execution", e);
            ScreenshotUtil.captureScreenshot(page, "TC_001_error");
            throw new FrameworkException("Test execution failed", e);
        }
        log.info("========== TEST EXECUTION COMPLETED ==========");
    }

    @AfterTest
    public void tearDown() {
        log.info("========== TEST TEARDOWN STARTED ==========");
        BrowserFactory.closeBrowser();
        log.info("Browser closed");
        log.info("========== TEST TEARDOWN COMPLETED ==========");
    }
}
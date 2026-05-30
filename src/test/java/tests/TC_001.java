package tests;

import exceptions.FrameworkException;
import utils.ConfigReader;

import org.apache.logging.log4j.LogManager;
import org.apache.logging.log4j.Logger;
import org.testng.Assert;
import org.testng.annotations.AfterTest;
import org.testng.annotations.BeforeTest;
import org.testng.annotations.Test;

import com.microsoft.playwright.Browser;
import com.microsoft.playwright.BrowserType;
import com.microsoft.playwright.Page;
import com.microsoft.playwright.Playwright;

public class TC_001 {

    private static final Logger log = LogManager.getLogger(TC_001.class);

    Playwright playwright;
    Browser browser;
    Page page;

    String baseUrl;
    boolean headless;
    int slowMo;

    @BeforeTest
    public void setUp() {
        log.info("========== TEST SETUP STARTED ==========");

        try {
            // Load config once per test class
            baseUrl = ConfigReader.getProperty("base.url");
            headless = ConfigReader.getBooleanProperty("headless", true);
            slowMo = ConfigReader.getIntProperty("slowMo", 0);

            log.info("Config loaded -> baseUrl={}, headless={}, slowMo={}",
                    baseUrl, headless, slowMo);

            playwright = Playwright.create();

            browser = playwright.chromium().launch(
                    new BrowserType.LaunchOptions()
                            .setHeadless(headless)
                            .setSlowMo(slowMo)
            );

            page = browser.newPage();

            log.info("Browser session initialized successfully");

        } catch (Exception e) {
            throw new FrameworkException("Failed to initialise test setup", e);
        }

        log.info("========== TEST SETUP COMPLETED ==========");
    }

    @Test
    public void testTextBoxForm() {
        log.info("========== TEST EXECUTION STARTED ==========");

        try {
            page.navigate(baseUrl);

            page.navigate(baseUrl + "/elements");
            page.click("span.text:has-text('Text Box')");

            page.fill("#userName", "John Doe");
            page.fill("#userEmail", "john.doe@test.com");
            page.fill("#currentAddress", "New Delhi, India");
            page.fill("#permanentAddress", "Bangalore, India");

            page.click("#submit");

            boolean isOutputVisible = page.isVisible("#output");
            Assert.assertTrue(isOutputVisible,
                    "Output div should be visible after submission");

            String outputText = page.textContent("#output");
            log.info("Form Output:\n{}", outputText);

        } catch (Exception e) {
            throw new FrameworkException("Test execution failed", e);
        }

        log.info("========== TEST EXECUTION COMPLETED ==========");
    }

    @AfterTest
    public void tearDown() {
        log.info("========== TEST TEARDOWN STARTED ==========");

        if (browser != null) browser.close();
        if (playwright != null) playwright.close();

        log.info("Browser and Playwright closed successfully");

        log.info("========== TEST TEARDOWN COMPLETED ==========");
    }
}

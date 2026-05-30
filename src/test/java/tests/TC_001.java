package tests;

import exceptions.FrameworkException;

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

    @BeforeTest
    public void setUp() {
        log.info("========== TEST SETUP STARTED ==========");
        try {
            playwright = Playwright.create();
            log.info("Playwright initialized");
            browser = playwright.chromium().launch(
                    new BrowserType.LaunchOptions().setHeadless(true)
            );
            log.info("Browser launched successfully");
            page = browser.newPage();
            log.info("New page created");
        } catch (Exception e) {
            throw new FrameworkException("Failed to initialise browser/Playwright", e);
        }
        log.info("========== TEST SETUP COMPLETED ==========");
    }

    @Test
    public void testTextBoxForm() {
        log.info("========== TEST EXECUTION STARTED ==========");
        try {
            page.navigate("https://demoqa.com");
            page.click("div.card-body:has-text('Elements')");
            page.click("span.text:has-text('Text Box')");

            page.fill("#userName", "John Doe");
            page.fill("#userEmail", "john.doe@test.com");
            page.fill("#currentAddress", "New Delhi, India");
            page.fill("#permanentAddress", "Bangalore, India");

            page.click("#submit");

            boolean isOutputVisible = page.isVisible("#output");
            Assert.assertTrue(isOutputVisible, "Output div should be visible after submission");

            log.info(page.textContent("#output"));
        } catch (Exception e) {
            throw new FrameworkException("Test execution failed: " + e.getMessage(), e);
        }
        log.info("========== TEST EXECUTION COMPLETED ==========");
    }

    @AfterTest
    public void tearDown() {
        log.info("========== TEST TEARDOWN STARTED ==========");
        if (browser != null) browser.close();
        if (playwright != null) playwright.close();
        log.info("========== TEST TEARDOWN COMPLETED ==========");
    }
}

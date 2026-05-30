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

public class TC_001 {

    private static final Logger log = LogManager.getLogger(TC_001.class);

    private Page page;
    private String baseUrl;

    @BeforeTest
    public void setUp() {
        log.info("========== TEST SETUP STARTED ==========");

        try {
            baseUrl = ConfigReader.getProperty("base.url");

            log.info("Base URL loaded: {}", baseUrl);

            page = BrowserFactory.getNewPage();

            log.info("Browser page created successfully");

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

        try {
            BrowserFactory.closeBrowser();
            log.info("Browser session closed via BrowserFactory");
        } catch (Exception e) {
            throw new FrameworkException("Teardown failed", e);
        }

        log.info("========== TEST TEARDOWN COMPLETED ==========");
    }
}
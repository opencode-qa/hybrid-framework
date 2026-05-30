package tests;

import com.microsoft.playwright.*;
import exceptions.FrameworkException;
import org.testng.Assert;
import org.testng.annotations.AfterTest;
import org.testng.annotations.BeforeTest;
import org.testng.annotations.Test;

public class TC_001 {

    Playwright playwright;
    Browser browser;
    Page page;

    @BeforeTest
    public void setUp() {
        System.out.println("========== TEST SETUP STARTED ==========");
        try {
            playwright = Playwright.create();
            System.out.println("Playwright initialized");
            browser = playwright.chromium().launch(
                    new BrowserType.LaunchOptions().setHeadless(true)
            );
            System.out.println("Browser launched successfully");
            page = browser.newPage();
            System.out.println("New page created");
        } catch (Exception e) {
            throw new FrameworkException("Failed to initialise browser/Playwright", e);
        }
        System.out.println("========== TEST SETUP COMPLETED ==========");
    }

    @Test
    public void testTextBoxForm() {
        System.out.println("========== TEST EXECUTION STARTED ==========");
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

            System.out.println(page.textContent("#output"));
        } catch (Exception e) {
            throw new FrameworkException("Test execution failed: " + e.getMessage(), e);
        }
        System.out.println("========== TEST EXECUTION COMPLETED ==========");
    }

    @AfterTest
    public void tearDown() {
        System.out.println("========== TEST TEARDOWN STARTED ==========");
        if (browser != null) browser.close();
        if (playwright != null) playwright.close();
        System.out.println("========== TEST TEARDOWN COMPLETED ==========");
    }
}
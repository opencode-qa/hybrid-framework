package tests;

import org.testng.Assert;
import org.testng.annotations.AfterTest;
import org.testng.annotations.BeforeTest;
import org.testng.annotations.Test;

import com.microsoft.playwright.Browser;
import com.microsoft.playwright.BrowserType;
import com.microsoft.playwright.Page;
import com.microsoft.playwright.Playwright;

public class TC_001 {

    Playwright playwright;
    Browser browser;
    Page page;

    @BeforeTest
    public void setUp() {

        System.out.println("========== TEST SETUP STARTED ==========");

        playwright = Playwright.create();
        System.out.println("Playwright initialized");

        browser = playwright.chromium().launch(
                new BrowserType.LaunchOptions().setHeadless(true)
        );
        System.out.println("Browser launched successfully");

        page = browser.newPage();
        System.out.println("New page created");

        System.out.println("========== TEST SETUP COMPLETED ==========");
    }

    @Test
    public void testTextBoxForm() {

        System.out.println("========== TEST EXECUTION STARTED ==========");

        // Navigate to website
        System.out.println("Navigating to DemoQA website...");
        page.navigate("https://demoqa.com");
        System.out.println("Successfully navigated to: " + page.url());

        // Click Elements card
        System.out.println("Clicking on 'Elements' card...");
        page.click("div.card-body:has-text('Elements')");
        System.out.println("'Elements' card clicked");

        // Click Text Box menu item
        System.out.println("Clicking on 'Text Box' menu...");
        page.click("span.text:has-text('Text Box')");
        System.out.println("'Text Box' menu clicked");

        // Fill form
        System.out.println("Filling Full Name...");
        page.fill("#userName", "John Doe");

        System.out.println("Filling Email...");
        page.fill("#userEmail", "john.doe@test.com");

        System.out.println("Filling Current Address...");
        page.fill("#currentAddress", "New Delhi, India");

        System.out.println("Filling Permanent Address...");
        page.fill("#permanentAddress", "Bangalore, India");

        System.out.println("Form filled successfully");

        // Submit form
        System.out.println("Clicking Submit button...");
        page.click("#submit");
        System.out.println("Form submitted successfully");

        // Validation
        System.out.println("Validating output section visibility...");
        boolean isOutputVisible = page.isVisible("#output");

        System.out.println("Output visibility status: " + isOutputVisible);

        Assert.assertTrue(
                isOutputVisible,
                "Output div should be visible after submission"
        );

        System.out.println("Assertion passed successfully");

        // Print output
        String outputText = page.textContent("#output");

        System.out.println("========== OUTPUT RECEIVED ==========");
        System.out.println(outputText);

        System.out.println("========== TEST EXECUTION COMPLETED ==========");
    }

    @AfterTest
    public void tearDown() {

        System.out.println("========== TEST TEARDOWN STARTED ==========");

        if (browser != null) {
            browser.close();
            System.out.println("Browser closed successfully");
        }

        if (playwright != null) {
            playwright.close();
            System.out.println("Playwright closed successfully");
        }

        System.out.println("========== TEST TEARDOWN COMPLETED ==========");
    }
}
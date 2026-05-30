package listeners;

import com.microsoft.playwright.Page;
import factory.BrowserFactory;
import org.apache.logging.log4j.LogManager;
import org.apache.logging.log4j.Logger;
import org.testng.ITestListener;
import org.testng.ITestResult;
import utils.ScreenshotUtil;

public class ScreenshotListener implements ITestListener {

    private static final Logger log = LogManager.getLogger(ScreenshotListener.class);

    @Override
    public void onTestFailure(ITestResult result) {

        String testName = result.getName();
        log.info("Test failed → capturing screenshot: {}", testName);

        Page page = BrowserFactory.getCurrentPage();

        if (page == null) {
            log.warn("No page available for screenshot: {}", testName);
            return;
        }

        ScreenshotUtil.captureScreenshot(page, testName);
    }
}
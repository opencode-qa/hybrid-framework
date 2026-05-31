package listeners;

import com.microsoft.playwright.Page;
import factory.BrowserFactory;
import org.apache.logging.log4j.LogManager;
import org.apache.logging.log4j.Logger;
import org.testng.ITestListener;
import org.testng.ITestResult;
import utils.ScreenshotUtil;

/**
 * TestNG listener that captures screenshots when a test fails.
 */
public class ScreenshotListener implements ITestListener {

    /**
     * Logger for this class.
     */
    private static final Logger LOG =
            LogManager.getLogger(ScreenshotListener.class);

    @Override
    public void onTestFailure(final ITestResult result) {
        final String testName = result.getName();
        LOG.info("Test failed → capturing screenshot: {}", testName);

        final Page page = BrowserFactory.getCurrentPage();

        if (page == null) {
            LOG.warn("No page available for screenshot: {}", testName);
            return;
        }

        ScreenshotUtil.captureScreenshot(page, testName);
    }
}

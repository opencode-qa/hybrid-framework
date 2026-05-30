package exceptions;

/**
 * Custom unchecked exception for framework‑specific failures.
 */
public class FrameworkException extends RuntimeException {
    public FrameworkException(String message) {
        super(message);
    }

    public FrameworkException(String message, Throwable cause) {
        super(message, cause);
    }
}
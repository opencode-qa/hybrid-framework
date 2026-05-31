package exceptions;

/**
 * Custom unchecked exception for framework-specific failures.
 */
public class FrameworkException extends RuntimeException {

    /**
     * Constructs a new exception with the specified detail message.
     *
     * @param message the detail message
     */
    public FrameworkException(final String message) {
        super(message);
    }

    /**
     * Constructs a new exception with the specified detail message and cause.
     *
     * @param message the detail message
     * @param cause   the underlying cause
     */
    public FrameworkException(final String message, final Throwable cause) {
        super(message, cause);
    }
}

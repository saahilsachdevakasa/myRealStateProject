public class RecursionGuard {

    private static Set<String> runKeys = new Set<String>();

    public static Boolean isFirstRun(String key) {
        if (runKeys.contains(key)) {
            return false;
        }
        runKeys.add(key);
        return true;
    }

    public static void reset(String key) {
        runKeys.remove(key);
    }

    @TestVisible
    static void resetAll() {
        runKeys.clear();
    }
}

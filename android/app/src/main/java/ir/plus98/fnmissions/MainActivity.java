package ir.plus98.fnmissions;

import android.annotation.SuppressLint;
import android.app.Activity;
import android.content.ActivityNotFoundException;
import android.content.Intent;
import android.graphics.Color;
import android.net.Uri;
import android.os.Bundle;
import android.view.View;
import android.view.Window;
import android.webkit.JavascriptInterface;
import android.webkit.WebResourceError;
import android.webkit.WebResourceRequest;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;

/**
 * Hosts the Fortnite Missions web app (the same PWA as in the browser).
 * Links to other sites (Telegram, GitHub) open outside the app; when the app
 * was never loaded and there is no connection, a bundled offline page shows.
 */
public class MainActivity extends Activity {
    private static final String OFFLINE_PAGE = "file:///android_asset/offline.html";
    private WebView web;
    private String appHost;

    @SuppressLint("SetJavaScriptEnabled")
    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        Window window = getWindow();
        window.setStatusBarColor(Color.parseColor("#1a0f33"));
        window.setNavigationBarColor(Color.parseColor("#1a0f33"));

        appHost = Uri.parse(BuildConfig.APP_URL).getHost();
        web = new WebView(this);
        web.setBackgroundColor(Color.parseColor("#1a0f33"));
        web.setOverScrollMode(View.OVER_SCROLL_NEVER);
        setContentView(web);

        WebSettings s = web.getSettings();
        s.setJavaScriptEnabled(true);
        s.setDomStorageEnabled(true);
        s.setDatabaseEnabled(true);
        s.setCacheMode(WebSettings.LOAD_DEFAULT);
        s.setAllowFileAccess(false);
        s.setAllowContentAccess(false);
        s.setMediaPlaybackRequiresUserGesture(true);
        s.setUserAgentString(s.getUserAgentString() + " FNMissionsApp/" + BuildConfig.VERSION_NAME);
        web.addJavascriptInterface(new Bridge(), "FNAndroid");

        web.setWebViewClient(new WebViewClient() {
            @Override
            public boolean shouldOverrideUrlLoading(WebView view, WebResourceRequest request) {
                Uri uri = request.getUrl();
                String host = uri.getHost();
                String current = view.getUrl() == null ? null : Uri.parse(view.getUrl()).getHost();
                // Stay inside for the app's own pages, including a redirect of
                // APP_URL to a custom domain; everything else opens outside.
                boolean inside = request.isRedirect()
                        || "file".equals(uri.getScheme())
                        || (host != null && (host.equals(appHost) || host.equals(current)));
                if (inside && ("https".equals(uri.getScheme()) || "file".equals(uri.getScheme()))) {
                    return false;
                }
                openOutside(uri);
                return true;
            }

            @Override
            public void onReceivedError(WebView view, WebResourceRequest request, WebResourceError error) {
                if (request.isForMainFrame()) {
                    view.loadUrl(OFFLINE_PAGE);
                }
            }
        });

        if (savedInstanceState != null) {
            web.restoreState(savedInstanceState);
        } else {
            web.loadUrl(BuildConfig.APP_URL);
        }
    }

    private void openOutside(Uri uri) {
        try {
            startActivity(new Intent(Intent.ACTION_VIEW, uri));
        } catch (ActivityNotFoundException ignored) {
            // nothing on the phone can open it
        }
    }

    /** Called by the offline page's retry button. */
    private class Bridge {
        @JavascriptInterface
        public void retry() {
            web.post(() -> web.loadUrl(BuildConfig.APP_URL));
        }
    }

    @Override
    protected void onSaveInstanceState(Bundle outState) {
        super.onSaveInstanceState(outState);
        web.saveState(outState);
    }

    @Override
    public void onBackPressed() {
        if (web.canGoBack() && !OFFLINE_PAGE.equals(web.getUrl())) {
            web.goBack();
        } else {
            super.onBackPressed();
        }
    }

    @Override
    protected void onResume() {
        super.onResume();
        web.onResume();
    }

    @Override
    protected void onPause() {
        web.onPause();
        super.onPause();
    }

    @Override
    protected void onDestroy() {
        web.destroy();
        super.onDestroy();
    }
}

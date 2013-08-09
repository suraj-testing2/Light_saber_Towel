part of streamy.runtime;

typedef Future RetryStrategy(Request request, int retryNum, e);

Future<bool> retryImmediately(Request request, int retryNum, e) => new Future.value(true);

class StreamyRpcException implements Exception {
  final int httpStatus;
  final Request request;
  final List<Map> errors;
  Map get error => errors[0];
  
  StreamyRpcException._private(this.httpStatus, this.request, this.errors);
}

class RetryingRequestHandler extends RequestHandler {
  
  final RequestHandler delegate;
  final RetryStrategy strategy;
  final List errorCodesToRetry;
  final int maxRetries;
  
  RetryingRequestHandler(this.delegate, {this.strategy: retryImmediately, this.maxRetries: 3, this.errorCodesToRetry: [500, 503]});
  
  Stream handle(Request request) {
    var strategy = this.strategy;
    if (request.local['retryStrategy'] != null) {
      strategy = request.local['retryStrategy'];
    }

    int retry = 0;
    
    Future doRpc() {
      return delegate.handle(request).single
        // A successful RPC returns from here.
        .catchError((e) {
          if (!_isRetryable(e)) {
            // Rethrow exceptions which can't be handled.
            throw e;
          }
          // We need to retry. retryFuture is a future that doesn't return a value, but indicates when
          // the call should be retried.
          var retryFuture = retryStrategy(request, ++retry, e);
          if (retry == maxRetries + 1) {
            // Time to give up.
            throw e;
          }
          return retryFuture.then((shouldRetry) {
            if (!shouldRetry) {
              throw e;
            }
            return doRpc();
          });
        });
    }
    
    return doRpc().asStream();
  }
  


import logging
import logging.config
import inspect



class NLogger(object):
    """docstring for NLogger"""

    OK = [True]
    ERR = [False]

    loglevels = ['debug','info', 'warning', 'error']

    @staticmethod
    def init(name, level):
        """ """

        # level = logging.__dict__[level]

        logger = logging.getLogger(name)
        logger.setLevel(level)
        # create file handler which logs even debug messages
        # fh = logging.FileHandler('nelnet.log')
        # fh.setLevel(level)
        # create console handler with a higher log level
        ch = logging.StreamHandler()
        ch.setLevel("DEBUG")
        # create formatter and add it to the handlers
        formatter = logging.Formatter(
                fmt='%(asctime)s.%(msecs)03d - %(name)s - %(levelname)s - %(message)s',
                datefmt='%H:%M:%S',
        )
        # fh.setFormatter(formatter)
        ch.setFormatter(formatter)
        # add the handlers to the logger
        # logger.addHandler(fh)
        logger.handlers.clear()
        logger.addHandler(ch)
        #
        return logger

    @staticmethod
    def deinit(inobject):
        """ """
        if 'logger' in inobject.__dict__:
            inobject.logger = None

    def wrap(lvl='INFO'):
        """ logging decorator maker """
        def logdec(func):
            def wrapper(self, *argv, **kwargv):
                """  """
                level = lvl

                res = func(self, *argv, **kwargv)

                try:
                    msg = 'func: %s - args: [ %s ] - kwargs: [ %s ] ---> %s' % (
                        func.__name__,
                        ', '.join([str(a) for a in argv]),
                        ', '.join(['%s=%s' % (str(a), kwargv[a]) for a in kwargv]),
                        str(res)
                    )
                    # msg = msg.replace('\r\n', '')
                    level = level.lower()

                    if level in NLogger.loglevels:
                        logger = getattr(self.logger, level)
                        logger(msg)

                except Exception as e:
                    # print(e)
                    pass

                return res
            return wrapper
        return logdec

    @staticmethod
    def current_level(logger, msg):
        _logger = getattr(logger, logging.getLevelName(logger.level).lower())
        _logger(msg)


if __name__ == '__main__':

    class TestObj(object):
        def __init__(self):
            pass

        @NLogger.wrap('DEBUG')
        def foo(self, data):
            if data:
                return ''.join(str(data))

        @NLogger.wrap('DEBUG')
        def foo2(self, data):
            if data:
                return False
            return 'ALARM!'

    test_obj = TestObj()
    test_obj.logger = NLogger.init('test log', 'DEBUG')

    test_obj.logger.debug('debug test message')

    test_obj.foo(None)
    test_obj.foo([0x00, 0x01])

    test_obj.foo2(None)
    test_obj.foo2([0x00, 0x01])
